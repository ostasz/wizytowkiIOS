
import { NextRequest, NextResponse } from 'next/server';
import { GoogleGenerativeAI } from '@google/generative-ai';
import * as cheerio from 'cheerio';

import { verifyAppAttest } from '@/lib/appAttest';

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || '');

export async function POST(req: NextRequest) {
    try {
        // 1. Verify App Attest
        const isValid = await verifyAppAttest(req);
        if (!isValid) {
            return NextResponse.json({ error: 'Unauthorized Device' }, { status: 403 });
        }

        const { organization, website, rawText } = await req.json();

        let contextData = `Nazwa firmy: ${organization}\nTekst z wizytówki: ${rawText}`;

        // 2. Scrape Website (if provided)
        if (website) {
            try {
                // Add protocol if missing
                let url = website;
                if (!url.startsWith('http')) url = `https://${url}`;

                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), 5000); // 5s timeout

                const webRes = await fetch(url, {
                    signal: controller.signal,
                    headers: {
                        'User-Agent': 'Mozilla/5.0 (Compatible; WizytownikAI/1.0)'
                    }
                });
                clearTimeout(timeoutId);

                if (webRes.ok) {
                    const html = await webRes.text();
                    const $ = cheerio.load(html);

                    // Remove scripts, styles for cleaner text
                    $('script').remove();
                    $('style').remove();

                    // Get meta description and body text (truncated)
                    const metaDesc = $('meta[name="description"]').attr('content') || '';
                    const bodyText = $('body').text().replace(/\s+/g, ' ').trim().slice(0, 4000); // Limit to 4k chars

                    contextData += `\n\nDane ze strony WWW (${url}):\nOpis Meta: ${metaDesc}\nTreść strony: ${bodyText}`;
                }
            } catch (e) {
                console.log("Scraping failed (ignoring):", e);
                contextData += `\n(Nie udało się pobrać treści ze strony WWW: ${website})`;
            }
        }

        // 3. Ask Gemini
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

        return NextResponse.json(JSON.parse(jsonString));

    } catch (error: any) {
        console.error("Enrich API Error:", error);
        return NextResponse.json({ error: error.message }, { status: 500 });
    }
}
