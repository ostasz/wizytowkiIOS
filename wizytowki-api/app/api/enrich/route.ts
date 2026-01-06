import { NextRequest, NextResponse } from 'next/server';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { z } from 'zod';
import * as cheerio from 'cheerio';
import { verifyAppAttest } from '@/lib/appAttest';
import { checkRateLimit } from '@/lib/ratelimit';
import { validateAndSanitizeURL, safeFetch } from '@/lib/ssrfProtection';

// 5. Check GEMINI_API_KEY at startup
if (!process.env.GEMINI_API_KEY) {
    throw new Error("GEMINI_API_KEY environment variable is not configured");
}

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

// 3. Input validation schema with size limits
const EnrichRequestSchema = z.object({
    organization: z.string().min(1).max(500),
    website: z.string().max(500).optional(),
    rawText: z.string().max(20000)
});

export async function POST(req: NextRequest) {
    try {
        // 1. Verify App Attest
        const attestResult = await verifyAppAttest(req);
        if (!attestResult) {
            return NextResponse.json({ error: 'Unauthorized Device' }, { status: 403 });
        }

        // Extract deviceId for rate limiting
        const attestToken = req.headers.get('x-attest-token');
        let deviceId = 'unknown';
        try {
            const decoded = Buffer.from(attestToken!, 'base64').toString('utf-8');
            const payload = JSON.parse(decoded);
            deviceId = payload.deviceId || 'unknown';
        } catch (e) {
            // Fallback
        }

        // 1. Rate Limiting (per device + per IP)
        const ip = req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip') || 'unknown-ip';
        const rateLimitKey = `enrich:${deviceId}:${ip}`;

        const rateLimitResult = await checkRateLimit(rateLimitKey);
        if (!rateLimitResult.success) {
            return NextResponse.json(
                { error: 'Rate limit exceeded. Please try again later.' },
                {
                    status: 429,
                    headers: {
                        'Retry-After': '60',
                        'X-RateLimit-Remaining': String(rateLimitResult.remaining || 0)
                    }
                }
            );
        }

        // 3. Validate request body
        const body = await req.json();
        const validationResult = EnrichRequestSchema.safeParse(body);

        if (!validationResult.success) {
            return NextResponse.json(
                { error: 'Invalid request', details: validationResult.error.issues },
                { status: 400 }
            );
        }

        const { organization, website, rawText } = validationResult.data;

        let contextData = `Nazwa firmy: ${organization}\nTekst z wizytówki: ${rawText}`;

        // 2. Scrape Website (if provided) - WITH SSRF PROTECTION
        if (website) {
            // CRITICAL: Validate URL to prevent SSRF attacks
            const urlValidation = await validateAndSanitizeURL(website);

            if (!urlValidation.valid) {
                console.warn(`🚨 SSRF attempt blocked: ${urlValidation.error} for URL: ${website}`);
                contextData += `\n(Nie udało się pobrać treści ze strony WWW: nieprawidłowy adres)`;
            } else {
                const url = urlValidation.sanitized!;

                // Safe fetch with size limits and redirect blocking
                const fetchResult = await safeFetch(url, 2 * 1024 * 1024); // 2MB max

                if (fetchResult.ok && fetchResult.text) {
                    const html = fetchResult.text;
                    const $ = cheerio.load(html);

                    // Remove scripts, styles for cleaner text
                    $('script').remove();
                    $('style').remove();

                    // Get meta description and body text (truncated)
                    const metaDesc = $('meta[name="description"]').attr('content') || '';
                    const bodyText = $('body').text().replace(/\s+/g, ' ').trim().slice(0, 4000); // Limit to 4k chars

                    contextData += `\n\nDane ze strony WWW (${url}):\nOpis Meta: ${metaDesc}\nTreść strony: ${bodyText}`;
                } else {
                    console.log("Scraping failed:", fetchResult.error);
                    contextData += `\n(Nie udało się pobrać treści ze strony WWW: ${website})`;
                }
            }
        }

        // Ask Gemini
        const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash-exp" });
        const prompt = `
    Na podstawie poniższych danych o firmie, stwórz krótki, profesjonalny opis B2B.

    DANE:
    """
    ${contextData}
    """

    ZADANIE:
    1. Napisz 2-3 zdaniowe podsumowanie czym firma się zajmuje (po polsku).
    2. Określ branżę.
    3. Znajdź lokalizację (miasto/kraj) jeśli jest w tekście.

    Zwróć czysty JSON:
    {
       "summary": "Krótki opis...",
       "industry": "np. IT / Budownictwo",
       "location": "np. Warszawa, Polska"
    }
    `;

        const result = await model.generateContent(prompt);
        const response = await result.response;
        const jsonString = response.text().replace(/```json/g, '').replace(/```/g, '').trim();

        const parsedData = JSON.parse(jsonString);

        // 6. Add security headers (no-store for PII)
        return NextResponse.json(parsedData, {
            headers: {
                'Cache-Control': 'no-store, private',
                'X-Content-Type-Options': 'nosniff'
            }
        });

    } catch (error: any) {
        // 4. Secure error handling - don't leak internals
        console.error("Enrich API Error:", error); // Log internally

        // Return generic error to client
        return NextResponse.json(
            { error: 'Internal Server Error' },
            { status: 500 }
        );
    }
}
