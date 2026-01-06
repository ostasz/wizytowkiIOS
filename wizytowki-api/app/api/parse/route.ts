import { NextRequest, NextResponse } from 'next/server';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { z } from 'zod';
import { verifyAppAttest } from '@/lib/appAttest';
import { checkRateLimit } from '@/lib/ratelimit';

// 5. Check GEMINI_API_KEY at startup
if (!process.env.GEMINI_API_KEY) {
  throw new Error("GEMINI_API_KEY environment variable is not configured");
}

// Initialize Gemini
const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

// 3. Input validation schema with size limit
const ParseRequestSchema = z.object({
  text: z.string().min(1, "Text cannot be empty").max(20000, "Text too long (max 20,000 characters)")
});

export async function POST(req: NextRequest) {
  try {
    // 1. Verify App Attest (Device Authentication)
    const attestResult = await verifyAppAttest(req);
    if (!attestResult) {
      return NextResponse.json({ error: 'Unauthorized Device' }, { status: 403 });
    }

    // Extract deviceId from attest token for rate limiting
    const attestToken = req.headers.get('x-attest-token');
    let deviceId = 'unknown';
    try {
      const decoded = Buffer.from(attestToken!, 'base64').toString('utf-8');
      const payload = JSON.parse(decoded);
      deviceId = payload.deviceId || 'unknown';
    } catch (e) {
      // Fallback to IP if deviceId extraction fails
    }

    // 1. Rate Limiting (per device + per IP)
    const ip = req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip') || 'unknown-ip';
    const rateLimitKey = `parse:${deviceId}:${ip}`;

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
    const validationResult = ParseRequestSchema.safeParse(body);

    if (!validationResult.success) {
      return NextResponse.json(
        { error: 'Invalid request', details: validationResult.error.issues },
        { status: 400 }
      );
    }

    const { text } = validationResult.data;

    // Call Gemini
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash-exp" });

    const prompt = `
    Jesteś ekspertem OCR i asystentem wprowadzania danych. 
    Twoim zadaniem jest przeanalizowanie surowego tekstu z wizytówki lub stopki mailowej.
    Priorytet: Zachowanie polskich znaków.

    Dane wejściowe:
    """
    ${text}
    """

    Zasady:
    1. Popraw oczywiste błędy OCR (np. "Emall" -> "Email").
    2. Formatuj numery telefonów do standardu (+48 XXX XXX XXX).
    3. Rozdziel Imię od Nazwiska.
    4. Ignoruj NIP/REGON przy szukaniu nazwy firmy (chyba że to jedyna nazwa).
    5. BARDZO WAŻNE: Napraw brakujące polskie znaki diakrytyczne (np. "Wieclawska" -> "Więcławska", "Lódz" -> "Łódź").

    Zwróć czysty JSON (bez markdown):
    {
        "firstName": string | null,
        "lastName": string | null,
        "organization": string | null,
        "jobTitle": string | null,
        "emailAddresses": string[],
        "phoneNumbers": string[],
        "websites": string[],
        "address": string | null,
        "note": string (tu wpisz puste, uzupełnimy później)
    }
    `;

    const result = await model.generateContent(prompt);
    const response = await result.response;
    const jsonString = response.text().replace(/```json/g, '').replace(/```/g, '').trim();

    // Parse and return result
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
    console.error("Parse API Error:", error); // Log internally

    // Return generic error to client
    return NextResponse.json(
      { error: 'Internal Server Error' },
      { status: 500 }
    );
  }
}
