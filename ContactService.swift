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
    
    func saveContact(_ parsed: ParsedContact, image: UIImage?, completion: @escaping (Result<Void, Error>) -> Void) {
        let contact = CNMutableContact()
        
        contact.givenName = parsed.firstName
        contact.familyName = parsed.lastName
        contact.organizationName = parsed.organization
        contact.jobTitle = parsed.jobTitle
        
        // Add phones
        contact.phoneNumbers = parsed.phoneNumbers.map {
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
        }
        
        // Add emails
        contact.emailAddresses = parsed.emailAddresses.map {
            CNLabeledValue(label: CNLabelWork, value: $0 as NSString)
        }
        
        // Add websites
        contact.urlAddresses = parsed.websites.map {
            CNLabeledValue(label: CNLabelURLAddressHomePage, value: $0 as NSString)
        }
        
        // Add Image
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
}
