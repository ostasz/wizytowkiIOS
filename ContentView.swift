import SwiftUI

struct ContentView: View {
    @State private var isShowingScanner = false
    @State private var scannedImage: UIImage?
    @State private var textRecognitionInProgress = false
    @State private var parsedContact: ParsedContact?
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    @StateObject var ocrService = OCRService()
    
    var body: some View {
        NavigationView {
            VStack {
                if let contact = parsedContact {
                    ContactEditForm(contact: Binding(
                        get: { contact },
                        set: { parsedContact = $0 }
                    ), image: scannedImage, onSave: saveContact, onCancel: reset)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Skaner Wizytówek")
            .sheet(isPresented: $isShowingScanner) {
                ScannerView(scannedImage: $scannedImage)
            }
            .onChange(of: scannedImage) { newImage in
                if let image = newImage {
                    performOCR(on: image)
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Status"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Zeskanuj wizytówkę, aby dodać kontakt")
                .font(.headline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding()
            
            Button(action: {
                isShowingScanner = true
            }) {
                Label("Skanuj teraz", systemImage: "camera.fill")
                    .font(.title3)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .overlay(
            Group {
                if textRecognitionInProgress {
                    ZStack {
                        Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                        ProgressView("Analizowanie...")
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                    }
                }
            }
        )
    }
    
    func performOCR(on image: UIImage) {
        textRecognitionInProgress = true
        ocrService.recognizeText(from: image) { contact in
            self.parsedContact = contact
            self.textRecognitionInProgress = false
        }
    }
    
    func saveContact() {
        guard let contact = parsedContact else { return }
        
        ContactService.shared.requestAccess { granted in
            if granted {
                ContactService.shared.saveContact(contact, image: scannedImage) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.alertMessage = "Kontakt zapisany pomyślnie!"
                            self.showAlert = true
                            self.reset() // Optional: auto reset after save
                        case .failure(let error):
                            self.alertMessage = "Błąd zapisu: \(error.localizedDescription)"
                            self.showAlert = true
                        }
                    }
                }
            } else {
                self.alertMessage = "Brak dostępu do kontaktów. Zmień to w Ustawieniach."
                self.showAlert = true
            }
        }
    }
    
    func reset() {
        scannedImage = nil
        parsedContact = nil
    }
}

struct ContactEditForm: View {
    @Binding var contact: ParsedContact
    var image: UIImage?
    var onSave: () -> Void
    var onCancel: () -> Void
    
    var body: some View {
        List {
            Section(header: Text("Zdjęcie")) {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                }
            }
            
            Section(header: Text("Dane Osobowe")) {
                TextField("Imię", text: $contact.firstName)
                TextField("Nazwisko", text: $contact.lastName)
                TextField("Firma", text: $contact.organization)
                TextField("Stanowisko", text: $contact.jobTitle)
            }
            
            Section(header: Text("Kontakt")) {
                ForEach(0..<contact.phoneNumbers.count, id: \.self) { index in
                    TextField("Telefon", text: $contact.phoneNumbers[index])
                        .keyboardType(.phonePad)
                }
                // Add button helper
                Button("Dodaj telefon") {
                    contact.phoneNumbers.append("")
                }
                
                ForEach(0..<contact.emailAddresses.count, id: \.self) { index in
                    TextField("Email", text: $contact.emailAddresses[index])
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                Button("Dodaj email") {
                    contact.emailAddresses.append("")
                }
            }
            
            Section(header: Text("Inne")) {
                 ForEach(0..<contact.websites.count, id: \.self) { index in
                    TextField("Strona WWW", text: $contact.websites[index])
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
            }
            
            Section {
                Button(action: onSave) {
                    Text("Zapisz do Kontaktów")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.blue)
                }
                
                Button(action: onCancel) {
                    Text("Anuluj")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.red)
                }
            }
        }
    }
}
