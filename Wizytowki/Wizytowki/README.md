# Skaner Wizytówek (iOS App)

Prosta, natywna aplikacja iOS napisana w SwiftUI, która pozwala:
1. Zeskanować wizytówkę (używając systemowego skanera dokumentów - VisionKit).
2. Rozpoznać tekst (OCR offline przez Vision Framework).
3. Inteligentnie wyciągnąć dane (Telefon, Email, Imię - używając NSDataDetector i heurystyk).
4. Edytować dane i zapisać je bezpośrednio w Kontatkach (Contacts Framework).

## Jak uruchomić projekt w Xcode?

W katalogu znajdują się pliki źródłowe `.swift`. Aby zbudować z nich aplikację:

1.  **Otwórz Xcode** i wybierz **"Create a new Xcode project"**.
2.  Wybierz szablon **App** (zakładka iOS).
3.  Ustawienia projektu:
    *   **Product Name**: `Wizytowki`
    *   **Interface**: SwiftUI
    *   **Language**: Swift
4.  Wybierz miejsce zapisu projektu.
5.  **Podmiana plików**:
    *   Przeciągnij pliki `ContentView.swift`, `ScannerView.swift`, `OCRModels.swift`, `ContactService.swift`, `WizytowkiApp.swift` do nawigatora projektu w Xcode (do folderu z żółtą ikonką folderu).
    *   Usuń domyślny plik `ContentView.swift` lub `WizytowkiApp.swift` stworzony przez Xcode, jeśli dubluje nazwy.
    *   Upewnij się, że zaznaczona jest opcja "Copy items if needed".

## Ważne: Uprawnienia (Info.plist)

Aplikacja wymaga dostępu do kamery i kontaktów. Musisz dodać dwa klucze w pliku `Info.plist` (lub w zakładce **TARGETS > Info > Custom iOS Target Properties**):

1.  **Privacy - Camera Usage Description** (`NSCameraUsageDescription`)
    *   Value: "Potrzebujemy aparatu do skanowania wizytówek."
2.  **Privacy - Contacts Usage Description** (`NSContactsUsageDescription`)
    *   Value: "Potrzebujemy dostępu, aby zapisać nowy kontakt w Twojej książce adresowej."

## Wymagania
*   iOS 13.0+ (Dla VisionKit i SwiftUI)
*   Najlepiej testować na fizycznym urządzeniu (Kamera).
