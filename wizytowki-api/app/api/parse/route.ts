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
    
    CRITICAL - Adres pocztowy:
    - NIGDY nie zwracaj adresu jako pojedynczego stringa!
    - ZAWSZE rozdziel adres na 4 osobne pola: street, postalCode, city, country
    - Jeśli adres to np. "29-100 Włoszczowa, ul. Jędrzejowska 79c", to:
      * street: "ul. Jędrzejowska 79c"
      * postalCode: "29-100"
      * city: "Włoszczowa"
      * country: "Polska"

    Zwróć DOKŁADNIE ten format JSON (bez markdown, bez komentarzy):
    {
        "firstName": string | null,
        "lastName": string | null,
        "organization": string | null,
        "jobTitle": string | null,
        "emailAddresses": string[],
        "phoneNumbers": string[],
        "websites": string[],
        "address": {
            "street": string | null,
            "postalCode": string | null,
            "city": string | null,
            "country": string | null
        },
        "note": ""
    }
    `;

    const result = await model.generateContent(prompt);
    const response = await result.response;
    const jsonString = response.text().replace(/```json/g, '').replace(/```/g, '').trim();

    // Parse and return result
    const parsedData = JSON.parse(jsonString);

    // POST-PROCESSING: Convert old address format (string) to new format (object)
    if (parsedData.address && typeof parsedData.address === 'string') {
      const addressString = parsedData.address as string;
      console.log('🔍 Original address from Gemini:', addressString);

      // Parse address string: "29-100 Włoszczowa, ul. Jędrzejowska 79c"
      // Pattern: [postal code] [city], [street]
      const match = addressString.match(/^(\d{2}-\d{3})\s+([^,]+),\s*(.+)$/);

      if (match) {
        parsedData.address = {
          street: match[3].trim(),
          postalCode: match[1].trim(),
          city: match[2].trim(),
          country: "Polska"
        };
        console.log('✅ Converted address (pattern 1):', parsedData.address);
      } else {
        // Fallback: try alternative pattern [street], [postal code] [city]
        const altMatch = addressString.match(/^(.+?),\s*(\d{2}-\d{3})\s+(.+)$/);
        if (altMatch) {
          parsedData.address = {
            street: altMatch[1].trim(),
            postalCode: altMatch[2].trim(),
            city: altMatch[3].trim(),
            country: "Polska"
          };
          console.log('✅ Converted address (pattern 2):', parsedData.address);
        } else {
          // Last resort: put everything in street
          parsedData.address = {
            street: addressString,
            postalCode: null,
            city: null,
            country: "Polska"
          };
          console.log('⚠️ Converted address (fallback):', parsedData.address);
        }
      }
    } else if (!parsedData.address) {
      // Ensure address is always an object
      parsedData.address = {
        street: null,
        postalCode: null,
        city: null,
        country: null
      };
      console.log('ℹ️ No address found, using empty object');
    } else {
      console.log('✅ Address already in correct format:', parsedData.address);
    }

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
