import Foundation
import Contacts
import UIKit

class ContactService {
    
    static let shared = ContactService()
    private let contactStore = CNContactStore()
    
    func requestAccess(completion: @escaping (Bool) -> Void) {
        contactStore.requestAccess(for: .contacts) { granted, error in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func saveContact(_ parsed: ParsedContact, image: UIImage?, location: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        let store = self.contactStore
        
        let firstName = (parsed.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lastName = (parsed.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🔍 Próba zapisu. Szukam duplikatów dla: '\(fullName)'")
        
        let keysToFetch = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            CNContactUrlAddressesKey, CNContactPostalAddressesKey,
            CNContactImageDataKey
            // WARNING: CNContactNoteKey is removed because reading notes requires special entitlement
        ] as [CNKeyDescriptor]
        
        do {
            var match: CNContact? = nil
            
            // STRATEGY 1: Search by Name
            if !fullName.isEmpty {
                let predicate = CNContact.predicateForContacts(matchingName: fullName)
                let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
                match = contacts.first
                if match != nil { print("✅ Znaleziono po nazwisku!") }
            }
            
            // STRATEGY 2: Search by Email (if Name failed)
            if match == nil {
                for email in parsed.emailAddresses {
                    print("🔍 Szukam po emailu: \(email)")
                    let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
                    let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
                    if let found = contacts.first {
                        match = found
                        print("✅ Znaleziono po emailu!")
                        break
                    }
                }
            }
            
            if let existing = match {
                // --- MERGE ---
                let mutableContact = existing.mutableCopy() as! CNMutableContact
                print("🔄 Scalanie kontaktu: \(mutableContact.givenName) \(mutableContact.familyName)")
                
                // Update Fields (Overwrite only if new has value)
                if let org = parsed.organization, !org.isEmpty { mutableContact.organizationName = org }
                if let job = parsed.jobTitle, !job.isEmpty { mutableContact.jobTitle = job }
                
                // Merge Phones (Add unique only)
                var currentPhones = mutableContact.phoneNumbers
                let newPhones = createPhoneNumbers(from: parsed.phoneNumbers)
                for newPhone in newPhones {
                    let newDigits = newPhone.value.stringValue.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    let exists = currentPhones.contains { existing in
                        let existingDigits = existing.value.stringValue.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                        return !newDigits.isEmpty && (existingDigits.contains(newDigits) || newDigits.contains(existingDigits))
                    }
                    if !exists { currentPhones.append(newPhone) }
                }
                mutableContact.phoneNumbers = currentPhones
                
                // Merge Emails
                var currentEmails = mutableContact.emailAddresses
                for emailStr in parsed.emailAddresses {
                    let exists = currentEmails.contains { ($0.value as String).lowercased() == emailStr.lowercased() }
                    if !exists {
                        currentEmails.append(CNLabeledValue(label: CNLabelWork, value: emailStr as NSString))
                    }
                }
                mutableContact.emailAddresses = currentEmails
                
                // Merge URLs
                var currentUrls = mutableContact.urlAddresses
                for urlStr in parsed.websites {
                    let exists = currentUrls.contains { ($0.value as String).lowercased() == urlStr.lowercased() }
                    if !exists {
                        currentUrls.append(CNLabeledValue(label: CNLabelURLAddressHomePage, value: urlStr as NSString))
                    }
                }
                mutableContact.urlAddresses = currentUrls
                
                // Address (Append new one if exists)
                if let address = parsed.address {
                    // Build address string for duplicate check
                    let addressComponents = [address.street, address.postalCode, address.city].compactMap { $0 }.filter { !$0.isEmpty }
                    if !addressComponents.isEmpty {
                        let addressString = addressComponents.joined(separator: " ")
                        // Check if address already exists to avoid duplication
                        let exists = mutableContact.postalAddresses.contains { $0.value.street.contains(addressString) }
                        if !exists {
                            let postalAddress = CNMutablePostalAddress()
                            postalAddress.street = address.street ?? ""
                            postalAddress.postalCode = address.postalCode ?? ""
                            postalAddress.city = address.city ?? ""
                            postalAddress.country = address.country ?? ""
                            mutableContact.postalAddresses.append(CNLabeledValue(label: CNLabelWork, value: postalAddress))
                        }
                    }
                }
                
                // WARNING: We CANNOT update the 'note' of an existing contact without the 'com.apple.developer.contacts.notes' entitlement.
                // Attempting to set it (even blindly) causes a crash because the key was not fetched.
                print("⚠️ Pomijam aktualizację notatki w trybie scalania (brak uprawnień systemowych do edycji notatek).")
                
                // Update Image
                if let image = image, let imageData = image.jpegData(compressionQuality: 0.9) {
                    mutableContact.imageData = imageData
                }
                
                let saveRequest = CNSaveRequest()
                saveRequest.update(mutableContact)
                try store.execute(saveRequest)
                print("💾 Zapisano zmiany (update)")
                completion(.success(()))
                
            } else {
                // --- CREATE NEW ---
                print("🆕 Tworzenie nowego kontaktu")
                createNewContact(parsed, image: image, location: location, completion: completion)
            }
            
        } catch {
            print("❌ Błąd zapisu: \(error)")
            completion(.failure(error))
        }
    }
    
    // Helper for creating new contact (Legacy logic moved here)
    private func createNewContact(_ parsed: ParsedContact, image: UIImage?, location: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        let contact = CNMutableContact()
        
        contact.givenName = parsed.firstName ?? ""
        contact.familyName = parsed.lastName ?? ""
        contact.organizationName = parsed.organization ?? ""
        contact.jobTitle = parsed.jobTitle ?? ""
        
        contact.phoneNumbers = createPhoneNumbers(from: parsed.phoneNumbers)
        
        contact.emailAddresses = parsed.emailAddresses.map {
            CNLabeledValue(label: CNLabelWork, value: $0 as NSString)
        }
        
        contact.urlAddresses = parsed.websites.map {
            CNLabeledValue(label: CNLabelURLAddressHomePage, value: $0 as NSString)
        }
        
        if let address = parsed.address {
            let addressComponents = [address.street, address.postalCode, address.city].compactMap { $0 }.filter { !$0.isEmpty }
            if !addressComponents.isEmpty {
                let postalAddress = CNMutablePostalAddress()
                postalAddress.street = address.street ?? ""
                postalAddress.postalCode = address.postalCode ?? ""
                postalAddress.city = address.city ?? ""
                postalAddress.country = address.country ?? ""
                contact.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: postalAddress)]
            }
        }
        
        // Add Note
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: Date())
        
        var finalNote = parsed.note 
        if !finalNote.isEmpty { finalNote += "\n\n—\n" }
        finalNote += "Utworzono: \(dateString)"
        if let loc = location { finalNote += "\nMiejsce: \(loc)" }
        finalNote += "\nSkaner Wizytówek AI"
        
        contact.note = finalNote
        
        if let image = image, let imageData = image.jpegData(compressionQuality: 0.9) {
            contact.imageData = imageData
        }
        
        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        
        do {
            try contactStore.execute(saveRequest)
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
    // Helper to generate phone numbers with labels
    private func createPhoneNumbers(from strings: [String]) -> [CNLabeledValue<CNPhoneNumber>] {
        return strings.map { numberString in
            var clean = numberString.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            if clean.hasPrefix("48") && clean.count == 11 {
                clean = String(clean.dropFirst(2))
            }
            
            var label = CNLabelWork
            if clean.count == 9 {
                if ["5", "6", "7", "8"].contains(clean.prefix(1)) || clean.hasPrefix("45") {
                     label = CNLabelPhoneNumberMobile
                }
            }
            return CNLabeledValue(label: label, value: CNPhoneNumber(stringValue: numberString))
        }
    }
}
