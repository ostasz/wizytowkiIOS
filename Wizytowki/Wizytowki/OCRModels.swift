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
    
    // Keys match the new Vercel API response schema exactly
    enum CodingKeys: String, CodingKey {
        case firstName, lastName, organization, jobTitle, emailAddresses, phoneNumbers, websites, address, note
    }
    
    // Manual init for empty state
    init(rawText: String = "") {
        self.rawText = rawText
        self.id = UUID()
    }
    
    // Decoder - simplified as backend guarantees arrays now
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.id = UUID()
        self.rawText = ""
        
        firstName = try? container.decode(String.self, forKey: .firstName)
        lastName = try? container.decode(String.self, forKey: .lastName)
        organization = try? container.decode(String.self, forKey: .organization)
        jobTitle = try? container.decode(String.self, forKey: .jobTitle)
        address = try? container.decode(String.self, forKey: .address)
        note = (try? container.decode(String.self, forKey: .note)) ?? ""
        
        // Backend now always sends arrays, but let's be safe
        phoneNumbers = (try? container.decode([String].self, forKey: .phoneNumbers)) ?? []
        emailAddresses = (try? container.decode([String].self, forKey: .emailAddresses)) ?? []
        websites = (try? container.decode([String].self, forKey: .websites)) ?? []
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
