import AppKit
import CoreText
import Foundation
import Observation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.app.screentranslate", category: "fontmanager")

@MainActor
@Observable
final class FontManager {
    static let shared = FontManager()

    // MARK: - Types

    enum FontSource: String, Codable {
        case bundled
        case downloaded
        case imported
    }

    struct InstalledFont: Identifiable, Equatable {
        let id: String            // e.g. "pretendard"
        let displayName: String
        let postScriptName: String
        let source: FontSource
        let fileURL: URL
    }

    struct CatalogFont: Identifiable, Codable, Equatable {
        let id: String
        let name: String
        let description: String
        let sizeBytes: Int
        let url: String
        let license: String
        let coverage: [String]
    }

    // MARK: - State

    var installedFonts: [InstalledFont] = []
    var catalogFonts: [CatalogFont] = []
    /// 폰트 다운로드 진행률 (0.0...1.0)
    var downloadProgress: Double = 0
    @ObservationIgnored private var registeredURLs: Set<URL> = []
    @ObservationIgnored private var downloadDelegate: DownloadProgressDelegate?

    // MARK: - Directories

    var fontsDirectoryURL: URL {
        // .applicationSupportDirectory is always available on macOS
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ScreenTranslate/Fonts", isDirectory: true)
    }

    // MARK: - Metadata Persistence

    /// 다운로드된 폰트의 카탈로그 ID/이름을 파일명과 매핑하여 저장
    private struct FontMetadata: Codable {
        var entries: [String: Entry]  // key = filename (e.g. "NotoSansKR-Regular.otf")

        struct Entry: Codable {
            let catalogId: String     // e.g. "noto-sans-kr"
            let displayName: String   // e.g. "Noto Sans KR"
        }
    }

    private var metadataFileURL: URL {
        fontsDirectoryURL.appendingPathComponent(".font-metadata.json")
    }

    private func loadMetadata() -> FontMetadata {
        guard let data = try? Data(contentsOf: metadataFileURL) else {
            return FontMetadata(entries: [:])
        }
        return (try? JSONDecoder().decode(FontMetadata.self, from: data)) ?? FontMetadata(entries: [:])
    }

    private func saveMetadata(_ metadata: FontMetadata) {
        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataFileURL, options: .atomic)
        } catch {
            logger.error("Failed to save font metadata: \(error.localizedDescription)")
        }
    }

    // MARK: - Init

    private init() {}

    // MARK: - Font Resolution

    /// Returns an NSFont for the current `popupFontName` setting.
    /// Falls back to system font if the named font is not found.
    func font(size: CGFloat) -> NSFont {
        let name = AppSettings.shared.popupFontName

        if name == "system" {
            return NSFont.systemFont(ofSize: size)
        }

        // Try installed fonts by id
        if let installed = installedFonts.first(where: { $0.id == name }) {
            if let font = NSFont(name: installed.postScriptName, size: size) {
                return font
            }
        }

        // Try direct PostScript name lookup
        if let font = NSFont(name: name, size: size) {
            return font
        }

        logger.warning("Font '\(name)' not found, falling back to system font")
        return NSFont.systemFont(ofSize: size)
    }

    /// Returns a SwiftUI Font for the current `popupFontName` setting.
    func swiftUIFont(size: CGFloat) -> Font {
        let name = AppSettings.shared.popupFontName

        if name == "system" {
            return .system(size: size)
        }

        if let installed = installedFonts.first(where: { $0.id == name }) {
            return .custom(installed.postScriptName, size: size)
        }

        // Try direct name
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }

        return .system(size: size)
    }

    // MARK: - Bundled Fonts

    /// Registers all bundled fonts from the app bundle's Fonts directory.
    func registerBundledFonts() {
        guard let fontsURL = Bundle.main.url(forResource: "Fonts", withExtension: nil) else {
            // Try individual font files in Resources/Fonts
            registerBundledFontFiles()
            return
        }
        registerFontsIn(directory: fontsURL, source: .bundled)
    }

    private func registerBundledFontFiles() {
        let extensions = ["otf", "ttf", "ttc"]
        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") {
                for url in urls {
                    registerSingleFont(at: url, source: .bundled)
                }
            }
        }
    }

    // MARK: - Installed Fonts (Application Support)

    /// Scans the Application Support/ScreenTranslate/Fonts/ directory for user fonts.
    func scanInstalledFonts() {
        let dir = fontsDirectoryURL
        guard FileManager.default.fileExists(atPath: dir.path) else { return }

        let metadata = loadMetadata()
        registerFontsIn(directory: dir, source: .downloaded, metadata: metadata)
    }

    // MARK: - Import / Remove

    /// Imports a font file from a user-selected URL into the fonts directory.
    func importFont(from sourceURL: URL) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let dir = fontsDirectoryURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let destURL = dir.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        registerSingleFont(at: destURL, source: .imported)
        logger.info("Imported font from \(sourceURL.lastPathComponent)")
    }

    /// Removes an installed font by its id.
    func removeFont(id: String) {
        guard let index = installedFonts.firstIndex(where: { $0.id == id }) else { return }
        let font = installedFonts[index]

        // Only remove downloaded/imported fonts, not bundled
        guard font.source != .bundled else {
            logger.warning("Cannot remove bundled font: \(id)")
            return
        }

        // Unregister
        var errorRef: Unmanaged<CFError>?
        CTFontManagerUnregisterFontsForURL(font.fileURL as CFURL, .process, &errorRef)
        registeredURLs.remove(font.fileURL)

        // Delete file
        do {
            try FileManager.default.removeItem(at: font.fileURL)
        } catch {
            logger.error("Failed to delete font file '\(id)': \(error.localizedDescription)")
        }

        // 메타데이터에서 제거
        var metadata = loadMetadata()
        metadata.entries.removeValue(forKey: font.fileURL.lastPathComponent)
        saveMetadata(metadata)

        installedFonts.remove(at: index)
        logger.info("Removed font: \(id)")
    }

    // MARK: - Catalog

    /// Loads the font catalog from the bundled JSON file.
    func loadCatalog() {
        guard let url = Bundle.main.url(forResource: "font-catalog", withExtension: "json", subdirectory: "Fonts") else {
            // Try without subdirectory
            guard let url = Bundle.main.url(forResource: "font-catalog", withExtension: "json") else {
                logger.warning("font-catalog.json not found in bundle")
                return
            }
            parseCatalog(at: url)
            return
        }
        parseCatalog(at: url)
    }

    private func parseCatalog(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let wrapper = try JSONDecoder().decode(CatalogWrapper.self, from: data)
            catalogFonts = wrapper.fonts
            logger.info("Loaded \(wrapper.fonts.count) fonts from catalog")
        } catch {
            logger.error("Failed to parse font catalog: \(error.localizedDescription)")
        }
    }

    private struct CatalogWrapper: Codable {
        let version: Int
        let fonts: [CatalogFont]
    }

    // MARK: - Download

    /// Downloads a catalog font and installs it, tracking progress.
    func downloadFont(_ catalogFont: CatalogFont) async throws {
        guard let url = URL(string: catalogFont.url) else {
            throw FontError.invalidURL
        }

        let dir = fontsDirectoryURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        downloadProgress = 0

        let tempURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let delegate = DownloadProgressDelegate(
                onProgress: { [weak self] fraction in
                    Task { @MainActor in
                        self?.downloadProgress = fraction
                    }
                },
                onComplete: { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: FontError.downloadFailed)
                    }
                }
            )
            self.downloadDelegate = delegate
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }

        downloadProgress = 1.0
        downloadDelegate = nil

        let fileName = url.lastPathComponent
        let destURL = dir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)

        // 메타데이터에 카탈로그 ID/이름 저장
        var metadata = loadMetadata()
        metadata.entries[fileName] = FontMetadata.Entry(
            catalogId: catalogFont.id,
            displayName: catalogFont.name
        )
        saveMetadata(metadata)

        registerSingleFont(at: destURL, source: .downloaded, catalogId: catalogFont.id, catalogDisplayName: catalogFont.name)
        logger.info("Downloaded and installed font: \(catalogFont.name)")
    }

    enum FontError: Error, LocalizedError {
        case invalidURL
        case registrationFailed
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid font download URL"
            case .registrationFailed: "Failed to register font"
            case .downloadFailed: "Font download failed"
            }
        }
    }

    // MARK: - Helpers

    /// Checks if a catalog font is already installed.
    func isInstalled(_ catalogFont: CatalogFont) -> Bool {
        installedFonts.contains(where: { $0.id == catalogFont.id })
    }

    /// Returns the installed font ID matching a catalog font, if installed.
    func installedFontId(for catalogFont: CatalogFont) -> String? {
        installedFonts.first(where: { $0.id == catalogFont.id })?.id
    }

    /// Extracts the PostScript name from a font file URL.
    func postScriptName(from url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first else {
            return nil
        }
        return CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
    }

    private func registerFontsIn(directory: URL, source: FontSource, metadata: FontMetadata? = nil) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }

        let fontExtensions: Set<String> = ["otf", "ttf", "ttc"]
        while let fileURL = enumerator.nextObject() as? URL {
            guard fontExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            let entry = metadata?.entries[fileURL.lastPathComponent]
            registerSingleFont(at: fileURL, source: source, catalogId: entry?.catalogId, catalogDisplayName: entry?.displayName)
        }
    }

    private func registerSingleFont(at url: URL, source: FontSource, catalogId: String? = nil, catalogDisplayName: String? = nil) {
        guard !registeredURLs.contains(url) else { return }

        var errorRef: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)

        if !success {
            if let error = errorRef?.takeRetainedValue() {
                let nsError = error as Error as NSError
                // Code 105 = already registered, that's fine
                if nsError.code != 105 {
                    logger.warning("Failed to register font at \(url.lastPathComponent): \(nsError.localizedDescription)")
                    return
                }
            }
        }

        registeredURLs.insert(url)

        // Extract PostScript name
        let psName = postScriptName(from: url) ?? url.deletingPathExtension().lastPathComponent

        // 카탈로그 ID가 있으면 사용, 없으면 파일명에서 생성
        let fontId: String
        let displayName: String
        if let cId = catalogId {
            fontId = cId
            displayName = catalogDisplayName ?? url.deletingPathExtension().lastPathComponent
        } else {
            let rawName = url.deletingPathExtension().lastPathComponent
            displayName = rawName
            fontId = rawName.lowercased()
                .replacingOccurrences(of: "-regular", with: "")
                .replacingOccurrences(of: " ", with: "-")
        }

        // Avoid duplicates
        guard !installedFonts.contains(where: { $0.id == fontId }) else { return }

        let installed = InstalledFont(
            id: fontId,
            displayName: displayName,
            postScriptName: psName,
            source: source,
            fileURL: url
        )
        installedFonts.append(installed)
        logger.info("Registered font: \(displayName) (\(psName)) from \(source.rawValue)")
    }
}

// MARK: - Download Delegate (FontManager 외부 — @MainActor 격리 방지)

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Double) -> Void
    let onComplete: @Sendable (URL?, Error?) -> Void
    /// 이중 resume 방지 플래그
    private let completed = OSAllocatedUnfairLock(initialState: false)

    init(onProgress: @escaping @Sendable (Double) -> Void, onComplete: @escaping @Sendable (URL?, Error?) -> Void) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    private func completeOnce(url: URL?, error: Error?) {
        let alreadyCompleted = completed.withLock { value -> Bool in
            if value { return true }
            value = true
            return false
        }
        guard !alreadyCompleted else { return }
        onComplete(url, error)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // HTTP 응답 코드 확인 (404 등 에러 응답을 파일로 저장하는 것 방지)
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let error = URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"
            ])
            completeOnce(url: nil, error: error)
            session.finishTasksAndInvalidate()
            return
        }

        // 임시 파일을 안전한 위치로 복사 (콜백 후 시스템이 삭제하므로)
        let tempDir = FileManager.default.temporaryDirectory
        let safeCopy = tempDir.appendingPathComponent(UUID().uuidString + ".fontdownload")
        try? FileManager.default.copyItem(at: location, to: safeCopy)
        completeOnce(url: safeCopy, error: nil)
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // totalBytesExpectedToWrite가 -1(unknown)이면 indeterminate (-1) 전달
        if totalBytesExpectedToWrite <= 0 {
            onProgress(-1)
        } else {
            let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            onProgress(fraction)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completeOnce(url: nil, error: error)
            session.finishTasksAndInvalidate()
        }
    }
}
