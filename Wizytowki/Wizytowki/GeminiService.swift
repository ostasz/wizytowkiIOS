import Foundation

class GeminiService {
    
    // 🔥 WAŻNE: Wklej tutaj swój klucz API z https://aistudio.google.com/app/apikey
    private let apiKey = "AIzaSyDAg--vn2haZorViV7XJsQbmsvUdSp9OHY"
    
    // Endpoint changed to gemini-2.5-flash (User Requested)
    private let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    // --- OCR PARSING ---
    
    func parseWithGemini(text: String) async throws -> ParsedContact {
        
        // 1. Prepare JSON Prompt
        let prompt = """
        Jesteś ekspertem OCR i asystentem wprowadzania danych.
        Twoim zadaniem jest przeanalizowanie surowego tekstu z wizytówki i wyodrębnienie danych strukturalnych.
        Priorytet: Polski.

        Zasady:
        1. Popraw oczywiste błędy OCR (np. "Emall" -> "Email").
        2. Formatuj numery telefonów (+48 XXX XXX XXX).
        3. Rozdziel Imię od Nazwiska.
        4. Ignoruj NIP/REGON przy szukaniu nazwy firmy.
        5. BARDZO WAŻNE: Napraw brakujące polskie znaki diakrytyczne (np. "Wieclawska" -> "Więcławska", "Lódz" -> "Łódź", "Sląski" -> "Śląski"). Jeśli imię lub nazwisko brzmi polsko, MUSISZ użyć poprawnej polskiej pisowni z ogonkami.

        Oto tekst z wizytówki:
        \"\"\"
        \(text)
        \"\"\"

        Zwróć kompletny JSON (bez markdown, czysty tekst):
        {
            "firstName": string | null,
            "lastName": string | null,
            "company": string | null,
            "jobTitle": string | null,
            "email": string | null,
            "phone": string | null, // lub array jeśli wiele
            "website": string | null, // lub array jeśli wiele
            "address": string | null
        }
        """
        
        // 2. Build Request Body
        let jsonBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "response_mime_type": "application/json"
            ]
        ]
        
        guard let url = URL(string: "\(urlString)?key=\(apiKey)") else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        
        // 3. Perform Request (Async)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Parse Gemini Response Structure
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = jsonResponse["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let textResponse = parts.first?["text"] as? String else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API Response"])
        }
            
        // Clean up potential markdown ```json wrapping
        let cleanJson = textResponse.replacingOccurrences(of: "```json", with: "")
                                    .replacingOccurrences(of: "```", with: "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let contactData = cleanJson.data(using: .utf8) else {
             throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Data conversion error"])
        }
        
        var contact = try JSONDecoder().decode(ParsedContact.self, from: contactData)
        contact.rawText = text // Preserve original text
        return contact
    }
    
    // --- COMPANY ENRICHMENT (Web + AI) ---
    
    struct EnrichmentData: Codable {
        let companySummary: String
        let industry: String?
        let hqOrLocation: String?
    }
    
    func enrichCompany(name: String, website: String, rawOcr: String) async throws -> EnrichmentData {
        // 1. Web Scraping (Live)
        var pageText = ""
        if !website.isEmpty, let url = URL(string: website.hasPrefix("http") ? website : "https://\(website)") {
            print("Pobieranie strony: \(url.absoluteString)")
            pageText = await fetchAndCleanPageContent(url: url)
        }
        
        // 2. Prepare Prompt
        let prompt = """
        Zadanie: Jako analityk biznesowy, uzupełnij notatkę o firmie (B2B).
        Działaj dokładnie jak w podanym przykładzie.
        
        Wejście:
        - Firma: \(name)
        - Website: \(website)
        - OCR Wizytówki: \"\"\"\(rawOcr.prefix(2000))\"\"\"
        - Treść strony WWW: \"\"\"\(pageText.prefix(10000))\"\"\"
        
        Zwróć CZYSTY JSON:
        {
          "companySummary": string,         // 3-6 krótkich, konkretnych zdań o działalności firmy po polsku.
          "industry": string|null,          // np. "Fotowoltaika", "Logistyka"
          "hqOrLocation": string|null       // Siedziba główna
        }
        """
        
        // 3. Request Body
        let jsonBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "response_mime_type": "application/json",
                "temperature": 0.2
            ]
        ]
        
        guard let url = URL(string: "\(urlString)?key=\(apiKey)") else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        
        // 4. Call API
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // 5. Parse Response
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = jsonResponse["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let textResponse = parts.first?["text"] as? String else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Enrichment API Response"])
        }
        
        let cleanJson = textResponse.replacingOccurrences(of: "```json", with: "")
                                    .replacingOccurrences(of: "```", with: "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let resultData = cleanJson.data(using: .utf8) else {
             throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Data conversion error"])
        }
        
        return try JSONDecoder().decode(EnrichmentData.self, from: resultData)
    }
    
    // Helper: Fetch HTML and strip tags
    private func fetchAndCleanPageContent(url: URL) async -> String {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8 // Szybki timeout
            // Udajemy przeglądarkę
            request.addValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            if let htmlString = String(data: data, encoding: .utf8) {
                // Prostym regexem usuwamy tagi HTML, style i skrypty
                return htmlString
                    .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("Web Scraping Error: \(error)")
        }
        return ""
    }
}
