import SwiftUI

struct ContentView: View {
    // --- State ---
    @State private var appMode: AppMode = .selection
    
    // Scanner State
    @State private var isShowingScanner = false
    @State private var scannedImage: UIImage?
    
    // Text Import State
    @State private var pastedText: String = ""
    
    // Shared Processing State
    @State private var isProcessing = false
    @State private var processingStatus = ""
    @State private var parsedContact: ParsedContact?
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // Services
    @StateObject var ocrService = OCRService()
    @StateObject var locationService = LocationService()
    let geminiService = GeminiService()
    
    // Modes
    enum AppMode {
        case selection  // Home Screen
        case textInput  // Pasting text
        case result     // Showing parsed contact
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // MARK: - Main Content Switcher
                switch appMode {
                case .selection:
                    selectionScreen
                    
                case .textInput:
                    textInputScreen
                    
                case .result:
                    if let contact = parsedContact {
                        ContactEditForm(
                            contact: Binding(
                                get: { contact },
                                set: { parsedContact = $0 }
                            ),
                            image: scannedImage,
                            onSave: saveContact,
                            onCancel: reset,
                            geminiService: geminiService
                        )
                    } else {
                        // Fallback
                        Text("Błąd danych")
                            .onAppear { appMode = .selection }
                    }
                }
                
                // MARK: - Overlays
                if isProcessing {
                    loadingOverlay
                }
            }
            .navigationTitle(navTitle)
            .sheet(isPresented: $isShowingScanner) {
                ScannerView(scannedImage: $scannedImage)
            }
            .onChange(of: scannedImage) { _, newImage in
                if let image = newImage {
                    processImageWithAI(image)
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Status"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .onAppear {
                locationService.requestLocation()
            }
        }
    }
    
    // MARK: - Computed Props
    var navTitle: String {
        switch appMode {
        case .selection: return "AI Wizytownik"
        case .textInput: return "Wklej Stopkę"
        case .result: return "Weryfikacja"
        }
    }
    
    // MARK: - Screens
    
    var selectionScreen: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 80))
                .foregroundColor(.purple)
                .padding(.bottom, 20)
            
            Text("Wybierz źródło")
                .font(.title2)
                .fontWeight(.bold)
            
            Button(action: {
                isShowingScanner = true
            }) {
                HStack {
                    Image(systemName: "camera.viewfinder")
                        .font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text("Skanuj Wizytówkę")
                            .fontWeight(.bold)
                        Text("Użyj aparatu")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(16)
                .shadow(radius: 5)
            }
            
            Button(action: {
                pastedText = ""
                appMode = .textInput
            }) {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                        .font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text("Wklej Tekst/Stopkę")
                            .fontWeight(.bold)
                        Text("Analiza danych z maila")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(16)
                .shadow(radius: 5)
            }
            
            Spacer()
            Text("Powered by Gemini 2.5 Flash")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(30)
    }
    
    var textInputScreen: some View {
        VStack(spacing: 20) {
            Text("Wklej treść maila lub stopkę poniżej:")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.top)
            
            TextEditor(text: $pastedText)
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            
            HStack(spacing: 20) {
                Button(action: { reset() }) {
                    Text("Anuluj")
                        .foregroundColor(.red)
                        .padding()
                }
                
                Button(action: { processTextWithAI(pastedText) }) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Analizuj (AI)")
                    }
                    .bold()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(pastedText.isEmpty ? Color.gray : Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(pastedText.isEmpty)
            }
        }
        .padding()
    }
    
    var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Text(processingStatus)
                    .foregroundColor(.white)
                    .font(.headline)
            }
            .padding(40)
            .background(Color.black.opacity(0.8))
            .cornerRadius(20)
        }
    }
    
    // MARK: - Logic
    
    func processImageWithAI(_ image: UIImage) {
        isProcessing = true
        processingStatus = "Czytanie tekstu (OCR)..."
        
        Task {
            // 1. Local OCR (Async)
            let rawText = await ocrService.recognizeRawText(from: image)
            
            guard !rawText.isEmpty else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.alertMessage = "Nie wykryto tekstu na zdjęciu."
                    self.showAlert = true
                }
                return
            }
            
            processTextWithGemini(rawText)
        }
    }
    
    func processTextWithAI(_ text: String) {
        processTextWithGemini(text)
    }
    
    func processTextWithGemini(_ text: String) {
        DispatchQueue.main.async {
            self.isProcessing = true
            self.processingStatus = "Analizowanie przez Gemini AI..."
        }
        
        Task {
            do {
                let contact = try await geminiService.parseWithGemini(text: text)
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.parsedContact = contact
                    self.appMode = .result // Switch to Edit View
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.alertMessage = "Błąd AI: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }
    
    func saveContact() {
        guard let contact = parsedContact else { return }
        
        ContactService.shared.requestAccess { granted in
            if granted {
                ContactService.shared.saveContact(contact, image: scannedImage, location: locationService.currentLocationName) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.alertMessage = "Zapisano w Kontaktach!"
                            self.showAlert = true
                            self.reset()
                        case .failure(let error):
                            self.alertMessage = "Błąd zapisu: \(error.localizedDescription)"
                            self.showAlert = true
                        }
                    }
                }
            } else {
                self.alertMessage = "Brak dostępu do kontaktów."
                self.showAlert = true
            }
        }
    }
    
    func reset() {
        scannedImage = nil
        parsedContact = nil
        pastedText = ""
        appMode = .selection // Go back to home
    }
}

// Keep ContactEditForm identical as it was, just ensure it's here:
struct ContactEditForm: View {
    @Binding var contact: ParsedContact
    var image: UIImage?
    var onSave: () -> Void
    var onCancel: () -> Void
    var geminiService: GeminiService // Need access to service
    
    @State private var isEnriching = false
    
    func enrichCompanyInfo() {
        let orgName = contact.organization ?? ""
        guard !orgName.isEmpty else { return }
        
        isEnriching = true
        
        Task {
            // Find url if exists
            let website = contact.websites.first ?? ""
            
            do {
                let enrichment = try await geminiService.enrichCompany(name: orgName, website: website, rawOcr: contact.rawText)
                
                DispatchQueue.main.async {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .short
                    dateFormatter.timeStyle = .short
                    let now = dateFormatter.string(from: Date())

                    let newNote = """
                    \(contact.note)
                    —
                    🤖 AI Info o firmie (\(now)):
                    \(enrichment.companySummary)
                    \(enrichment.industry != nil ? "Branża: \(enrichment.industry!)" : "")
                    \(enrichment.hqOrLocation != nil ? "Lokalizacja: \(enrichment.hqOrLocation!)" : "")
                    """
                    
                    self.contact.note = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.isEnriching = false
                }
            } catch {
                DispatchQueue.main.async {
                    print("Enrichment Error: \(error)")
                    self.isEnriching = false
                }
            }
        }
    }
    
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
            
            Section(header: Text("Dane z AI")) {
                TextField("Imię", text: Binding(get: { contact.firstName ?? "" }, set: { contact.firstName = $0 }))
                TextField("Nazwisko", text: Binding(get: { contact.lastName ?? "" }, set: { contact.lastName = $0 }))
                TextField("Firma", text: Binding(get: { contact.organization ?? "" }, set: { contact.organization = $0 }))
                TextField("Stanowisko", text: Binding(get: { contact.jobTitle ?? "" }, set: { contact.jobTitle = $0 }))
            }
            
            Section(header: Text("Adres")) {
                TextField("Ulica", text: Binding(
                    get: { contact.address?.street ?? "" },
                    set: { newValue in
                        if contact.address == nil {
                            contact.address = PostalAddress()
                        }
                        contact.address?.street = newValue
                    }
                ))
                
                HStack {
                    TextField("Kod", text: Binding(
                        get: { contact.address?.postalCode ?? "" },
                        set: { newValue in
                            if contact.address == nil {
                                contact.address = PostalAddress()
                            }
                            contact.address?.postalCode = newValue
                        }
                    ))
                    .keyboardType(.numbersAndPunctuation)
                    
                    TextField("Miasto", text: Binding(
                        get: { contact.address?.city ?? "" },
                        set: { newValue in
                            if contact.address == nil {
                                contact.address = PostalAddress()
                            }
                            contact.address?.city = newValue
                        }
                    ))
                }
                
                TextField("Kraj", text: Binding(
                    get: { contact.address?.country ?? "" },
                    set: { newValue in
                        if contact.address == nil {
                            contact.address = PostalAddress()
                        }
                        contact.address?.country = newValue
                    }
                ))
            }
            
            Section(header: Text("Kontakt")) {
                ForEach(0..<contact.phoneNumbers.count, id: \.self) { index in
                    TextField("Telefon", text: $contact.phoneNumbers[index])
                        .keyboardType(.phonePad)
                }
                
                ForEach(0..<contact.emailAddresses.count, id: \.self) { index in
                    TextField("Email", text: $contact.emailAddresses[index])
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
            }
            
            if !contact.websites.isEmpty {
                 Section(header: Text("WWW")) {
                     ForEach(0..<contact.websites.count, id: \.self) { index in
                        TextField("Strona", text: $contact.websites[index])
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                    }
                }
            }
            
            Section(header: Text("O Firmie (B2B)")) {
                if isEnriching {
                    HStack {
                        ProgressView()
                        Text("Analizowanie strony WWW...")
                            .foregroundColor(.gray)
                    }
                } else {
                    Button(action: enrichCompanyInfo) {
                        Label("Uzupełnij info o firmie (AI)", systemImage: "sparkles")
                            .foregroundColor(.purple)
                    }
                }
                
                if !contact.note.isEmpty {
                    TextEditor(text: $contact.note)
                        .frame(height: 150)
                        .font(.custom("Menlo", size: 12)) // Monospace font for better layout reading
                }
            }
            
            Section {
                Button(action: onSave) {
                    Text("Zapisz Kontakt")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .listRowBackground(Color.clear)
                
                Button(action: onCancel) {
                    Text("Anuluj")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.red)
                }
            }
        }
    }
}
