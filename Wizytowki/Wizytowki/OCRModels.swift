import Foundation
import Vision
import UIKit
import Combine

// Make it Codable so we can parse JSON from Gemini directly
struct ParsedContact: Identifiable, Equatable, Codable {
    var id = UUID()
    var rawText: String = ""
    
    var firstName: String?
    var lastName: String?
    var organization: String?
    var jobTitle: String?
    var phoneNumbers: [String] = []
    var emailAddresses: [String] = []
    var websites: [String] = []
    var address: String?
    var note: String = "" // New field for AI Enrichment
    
    // Custom keys to match Gemini JSON format if needed, 
    // but we will instruct Gemini to use specific keys.
    enum CodingKeys: String, CodingKey {
        case firstName, lastName, organization = "company", jobTitle, email, phone, website, address
    }
    
    // Manual init for empty state
    init(rawText: String = "") {
        self.rawText = rawText
        self.id = UUID()
    }
    
    // Decoder to handle single string vs array issues from AI
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = UUID()
        self.rawText = "" // AI result usually doesn't return raw text field, we fill it later
        
        firstName = try? container.decode(String.self, forKey: .firstName)
        lastName = try? container.decode(String.self, forKey: .lastName)
        organization = try? container.decode(String.self, forKey: .organization)
        jobTitle = try? container.decode(String.self, forKey: .jobTitle)
        address = try? container.decode(String.self, forKey: .address)
        
        // AI might return single string or array, handle both
        if let singlePhone = try? container.decode(String.self, forKey: .phone) {
            phoneNumbers = [singlePhone]
        } else if let arrayPhone = try? container.decode([String].self, forKey: .phone) {
            phoneNumbers = arrayPhone
        }
        
        if let singleEmail = try? container.decode(String.self, forKey: .email) {
            emailAddresses = [singleEmail]
        } else if let arrayEmail = try? container.decode([String].self, forKey: .email) {
            emailAddresses = arrayEmail
        }
        
        if let singleWeb = try? container.decode(String.self, forKey: .website) {
            websites = [singleWeb]
        } else if let arrayWeb = try? container.decode([String].self, forKey: .website) {
            websites = arrayWeb
        }
    }
    
    func encode(to encoder: Encoder) throws {
        // Encoding implementation if needed
    }
}

class OCRService: ObservableObject {
    
    // Perform OCR on a UIImage
    // Returns RAW TEXT now - Async version
    func recognizeRawText(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        
        return await Task.detached(priority: .userInitiated) {
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            
            return await withCheckedContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                        continuation.resume(returning: "")
                        return
                    }
                    
                    // Extract all text blocks sorted by Y position
                    let textLines = observations.compactMap { $0.topCandidates(1).first?.string }
                    let fullText = textLines.joined(separator: "\n")
                    continuation.resume(returning: fullText)
                }
                
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                
                do {
                    try requestHandler.perform([request])
                } catch {
                    // If perform fails synchronously
                    continuation.resume(returning: "")
                }
            }
        }.value
    }
}
