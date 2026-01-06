import Foundation
import Vision
import UIKit
import Combine

struct ParsedContact: Identifiable, Equatable {
    var id = UUID()
    var rawText: String = ""
    
    var firstName: String = ""
    var lastName: String = ""
    var organization: String = ""
    var jobTitle: String = ""
    var phoneNumbers: [String] = []
    var emailAddresses: [String] = []
    var websites: [String] = []
    var address: String = ""
    
    /// Helper to verify if contact has minimum required data
    var isValid: Bool {
        !firstName.isEmpty || !organization.isEmpty || !phoneNumbers.isEmpty
    }
}

class OCRService: ObservableObject {
    
    // Perform OCR on a UIImage
    func recognizeText(from image: UIImage, completion: @escaping (ParsedContact) -> Void) {
        guard let cgImage = image.cgImage else { return }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                print("OCR Error: \(String(describing: error))")
                completion(ParsedContact())
                return
            }
            
            // 1. Extract all text blocks sorted by Y position (top to bottom)
            let textLines = observations.compactMap { $0.topCandidates(1).first?.string }
            let fullText = textLines.joined(separator: "\n")
            
            // 2. Parse the text intelligently
            let contact = self?.parseContactInfo(from: textLines, fullText: fullText) ?? ParsedContact(rawText: fullText)
            
            DispatchQueue.main.async {
                completion(contact)
            }
        }
        
        // Settings for accuracy
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // You can add supported languages if needed, e.g. ["pl-PL", "en-US"]
        
        do {
            try requestHandler.perform([request])
        } catch {
            print("Unable to perform OCR request: \(error)")
            completion(ParsedContact())
        }
    }
    
    // Smarter heuristic parser
    private func parseContactInfo(from lines: [String], fullText: String) -> ParsedContact {
        var contact = ParsedContact(rawText: fullText)
        
        // 1. First, extract structured data (phones, emails, urls)
        // We do this first because these are easier to identify confidently.
        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType([.phoneNumber, .link, .address]).rawValue)
            let matches = detector.matches(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count))
            
            for match in matches {
                switch match.resultType {
                case .phoneNumber:
                    if let number = match.phoneNumber {
                        contact.phoneNumbers.append(number)
                    }
                case .link:
                    if let url = match.url {
                        if url.scheme == "mailto" {
                            contact.emailAddresses.append(url.absoluteString.replacingOccurrences(of: "mailto:", with: ""))
                        } else {
                            contact.websites.append(url.absoluteString)
                        }
                    } else if let email = match.url?.absoluteString, email.contains("@") {
                         contact.emailAddresses.append(email)
                    }
                default: break
                }
            }
            
            // Backup Email Regex
            let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
            let capturedEmails = self.matches(for: emailRegex, in: fullText)
            for mail in capturedEmails {
                if !contact.emailAddresses.contains(mail) {
                    contact.emailAddresses.append(mail)
                }
            }
        } catch {
            print("Data Detector Error: \(error)")
        }
        
        // 2. Filter out lines that are definitely NOT names/titles (phones, emails, urls)
        // We keep the original index to understand relative positioning (above/below)
        var candidateLines: [(index: Int, text: String)] = []
        
        for (index, line) in lines.enumerated() {
            let lowerLine = line.lowercased()
             // Check if line is mostly a phone number or email or url
            if contact.emailAddresses.contains(where: { line.contains($0) }) { continue }
            if contact.websites.contains(where: { line.contains($0) }) { continue }
            
            // Skip headers usually found on cards
            if ["nip:", "regon:", "tel.", "fax", "mobile", "kom.", "e-mail:"].contains(where: { lowerLine.contains($0) }) { continue }
            
            // Skip lines that are too short to be a name
            if line.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 { continue }
            
            candidateLines.append((index, line))
        }
        
        // 3. LOGIC: Identify Name using Email correlation (Strongest Signal)
        // e.g. "jakub.baczek@..." matches "Jakub Bączek"
        var nameLineIndex: Int? = nil
        
        if let firstEmail = contact.emailAddresses.first {
            let userPart = firstEmail.components(separatedBy: "@").first?.lowercased().replacingOccurrences(of: ".", with: "") ?? ""
            
            // Find line that looks like the email user part
            for candidate in candidateLines {
                // Remove diacritics and spaces for comparison
                let normalizedLine = candidate.text.lowercased()
                    .folding(options: .diacriticInsensitive, locale: .current)
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ".", with: "")
                
                // Check if email contains the name (e.g. jakubbaczek contains jakub) OR name contains email part
                // We use a simple containment check which covers 90% of business/corporate emails
                if !userPart.isEmpty && normalizedLine.contains(userPart) {
                    nameLineIndex = candidate.index
                    
                    // Assign Name
                    let parts = candidate.text.components(separatedBy: " ")
                    if parts.count >= 2 {
                        contact.firstName = parts.first ?? ""
                        contact.lastName = parts.dropFirst().joined(separator: " ")
                    } else {
                        contact.lastName = candidate.text
                    }
                    break
                }
            }
        }
        
        // 4. LOGIC: Identify Job Title to help find Name (if Email logic failed)
        // Job titles are often below the name.
        let jobKeywords = ["manager", "director", "ceo", "developer", "engineer", "prezes", "dyrektor", "kierownik", "specjalista", "konsultant", "sales", "account", "head of", "owner", "właściciel"]
        
        var jobTitleIndex: Int? = nil
        
        for candidate in candidateLines {
            if jobKeywords.contains(where: { candidate.text.lowercased().contains($0) }) {
                contact.jobTitle = candidate.text
                jobTitleIndex = candidate.index
                break
            }
        }
        
        // If we haven't found name yet, but we found a job title
        if nameLineIndex == nil, let jIndex = jobTitleIndex {
            // The name is likely the candidate line IMMEDIATELY ABOVE the job title
            if let nameCandidate = candidateLines.last(where: { $0.index < jIndex }) {
                nameLineIndex = nameCandidate.index
                let parts = nameCandidate.text.components(separatedBy: " ")
                if parts.count >= 2 {
                     contact.firstName = parts.first ?? ""
                     contact.lastName = parts.dropFirst().joined(separator: " ")
                } else {
                    contact.lastName = nameCandidate.text
                }
            }
        }
        
        // 5. Fallback: If still no name, take the FIRST candidate line that looks reasonable
        if nameLineIndex == nil, let firstCandidate = candidateLines.first {
             // (Simple Heuristic: First line is name)
             nameLineIndex = firstCandidate.index
             let parts = firstCandidate.text.components(separatedBy: " ")
             if parts.count >= 2 {
                 contact.firstName = parts.first ?? ""
                 contact.lastName = parts.dropFirst().joined(separator: " ")
             } else {
                 contact.lastName = firstCandidate.text
             }
        }
        
        // 6. Identify Organization
        // Any candidate line ABOVE the name is likely the Organization (Logo)
        // Or if Name is first, organization might be extracted from Email Domain or bottom line
        if let nIndex = nameLineIndex {
            // Look for lines ABOVE name
            if let orgCandidate = candidateLines.first(where: { $0.index < nIndex }) {
                 contact.organization = orgCandidate.text
            }
            // If no lines above name, and no organization set yet, maybe the line BELOW job title is address/company info?
            // (Skipping for now to avoid noise)
        }
        
        // Fallback for organization: use email domain if still empty
        if contact.organization.isEmpty, let email = contact.emailAddresses.first {
             let domain = email.components(separatedBy: "@").last?.components(separatedBy: ".").first
             if let dom = domain {
                 contact.organization = dom.capitalized
             }
        }

        return contact
    }
    
    private func matches(for regex: String, in text: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            return results.map {
                String(text[Range($0.range, in: text)!])
            }
        } catch {
            return []
        }
    }
}
