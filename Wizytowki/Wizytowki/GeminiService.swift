
import Foundation

class GeminiService {
    // SECURITY UPDATE:
    // API Key has been removed. Logic moved to secure backend.
    private let baseUrl = "https://wizytowki-ios.vercel.app/api"
    private let appVersionSecret = "1.0" // Simple header protection
    
    // MARK: - 1. Parse Image Text (OCR -> JSON)
    func parseWithGemini(text: String, completion: @escaping (Result<ParsedContact, Error>) -> Void) {
        guard let url = URL(string: "\(baseUrl)/parse") else {
            completion(.failure(NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Security Header
        request.addValue(appVersionSecret, forHTTPHeaderField: "x-app-version")
        
        // Simple Body: { "text": "..." }
        let body: [String: Any] = ["text": text]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(.failure(error))
            return
        }
        
        print("🚀 Sending request to Secure API: \(baseUrl)/parse")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "GeminiService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            
            // Debug: Print raw JSON
            if let str = String(data: data, encoding: .utf8) {
                print("📩 Received JSON: \(str)")
            }
            
            do {
                var parsedContact = try JSONDecoder().decode(ParsedContact.self, from: data)
                // Inject Raw Text back into the object for downstream logic (like enrichment)
                parsedContact.rawText = text
                completion(.success(parsedContact))
            } catch {
                print("❌ JSON Parsing Error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }
    
    // Async wrapper for Parse
    func parseWithGemini(text: String) async throws -> ParsedContact {
        return try await withCheckedThrowingContinuation { continuation in
            parseWithGemini(text: text) { result in
                switch result {
                case .success(let contact):
                    continuation.resume(returning: contact)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 2. Enrich Company Info (B2B)
    func enrichCompany(name: String, website: String, rawOcr: String) async throws -> CompanyEnrichment {
        guard let url = URL(string: "\(baseUrl)/enrich") else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(appVersionSecret, forHTTPHeaderField: "x-app-version")
        
        let body: [String: Any] = [
            "organization": name,
            "website": website,
            "rawText": rawOcr
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        print("🚀 Sending B2B Enrichment request...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "GeminiService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Server Error"])
        }
        
        let result = try JSONDecoder().decode(CompanyEnrichment.self, from: data)
        return result
    }
}

// Public Enriched Model (Matches Backend Response)
struct CompanyEnrichment: Codable {
    let summary: String
    let industry: String?
    let location: String? 
    
    // Compatible properties for existing code
    var companySummary: String { return summary }
    var hqOrLocation: String? { return location }
}
