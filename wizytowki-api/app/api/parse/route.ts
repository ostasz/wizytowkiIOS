
import { NextRequest, NextResponse } from 'next/server';
import { GoogleGenerativeAI } from '@google/generative-ai';

// Initialize Gemini
const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || '');

import { verifyAppAttest } from '@/lib/appAttest';

export async function POST(req: NextRequest) {
  try {
    // 1. Verify App Attest (Device Authentication)
    const isValid = await verifyAppAttest(req);
    if (!isValid) {
      return NextResponse.json({ error: 'Unauthorized Device' }, { status: 403 });
    }

    // 2. Parse Body
    const { text } = await req.json();

    if (!text) {
      return NextResponse.json({ error: 'Missing text parameter' }, { status: 400 });
    }

    // 3. Call Gemini
    // Switched back to 2.0-flash-exp as 1.5-flash returned 404 for this API key context
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

    // 4. Return Result
    return NextResponse.json(JSON.parse(jsonString));

  } catch (error: any) {
    console.error("API Error:", error);
    return NextResponse.json({ error: error.message || 'Internal Server Error' }, { status: 500 });
  }
}
