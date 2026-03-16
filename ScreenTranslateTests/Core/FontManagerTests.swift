import AppKit
import Foundation
import Testing
@testable import ScreenTranslate

@Suite(.serialized)
struct FontManagerTests {

    @Test("shared singleton exists")
    func sharedExists() {
        let manager = FontManager.shared
        #expect(manager != nil)
    }

    @Test("default font returns system font")
    @MainActor
    func defaultFontIsSystem() {
        let key = "com.screentranslate.popupFontName"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set("system", forKey: key)
        let font = FontManager.shared.font(size: 14)
        #expect(font.familyName == NSFont.systemFont(ofSize: 14).familyName)
    }

    @Test("registerBundledFonts does not crash")
    @MainActor
    func registerBundledFontsNoCrash() {
        // registerBundledFonts should not throw or crash regardless of environment
        FontManager.shared.registerBundledFonts()
        // In test runner, Bundle.main points to xctest bundle, not the app bundle,
        // so bundled fonts may not be found. Verify no crash occurred.
        // When running inside the app, Pretendard would be registered.
        let hasPretendard = FontManager.shared.installedFonts.contains { $0.id == "pretendard" }
        if Bundle.main.url(forResource: "Pretendard-Regular", withExtension: "otf", subdirectory: "Fonts") != nil {
            #expect(hasPretendard)
        }
        // No crash is the primary assertion
    }

    @Test("loadCatalog parses bundled JSON")
    @MainActor
    func loadCatalogParses() {
        FontManager.shared.loadCatalog()
        #expect(!FontManager.shared.catalogFonts.isEmpty)
        #expect(FontManager.shared.catalogFonts.first?.id == "noto-sans-kr")
    }

    @Test("font fallback for unknown font name")
    @MainActor
    func unknownFontFallback() {
        let key = "com.screentranslate.popupFontName"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set("nonexistent-font-xyz", forKey: key)
        let font = FontManager.shared.font(size: 14)
        #expect(font.familyName == NSFont.systemFont(ofSize: 14).familyName)
    }

    @Test("fontsDirectory creates Application Support subdirectory")
    @MainActor
    func fontsDirectoryCreation() {
        let dir = FontManager.shared.fontsDirectoryURL
        #expect(dir.lastPathComponent == "Fonts")
        #expect(dir.pathComponents.contains("ScreenTranslate"))
    }
}
