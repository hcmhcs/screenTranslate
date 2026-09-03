import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.app.screentranslate", category: "historystore")

/// 히스토리 SwiftData 스토어의 위치·복구·이전을 담당한다.
///
/// H2 배경: 기본 ModelContainer는 비샌드박스 앱에서 `~/Library/Application Support/default.store`를
/// 쓴다. 다른 앱과 겹칠 수 있는 공용 경로이고, 기존 복구 코드는 `URL.path()`의 퍼센트 인코딩 때문에
/// 파일을 지우지 못해 항상 인메모리로 떨어졌다. 앱 전용 폴더로 옮기고 복구 경로를 고친다.
enum HistoryStore {
    private static let storeSuffixes = ["", "-shm", "-wal"]

    /// 앱 전용 위치: ~/Library/Application Support/ScreenTranslate/history.store
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "ScreenTranslate", directoryHint: .isDirectory)
            .appending(path: "history.store")
    }

    /// 1.5.2 이하가 쓰던 위치: ~/Library/Application Support/default.store
    static var legacyStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// 새 위치에 스토어가 없고 기존 위치에 있으면 세 파일(.store/-shm/-wal)을 복사한다.
    /// 기존 파일은 지우지 않는다 (다른 앱의 파일일 가능성을 배제할 수 없다).
    /// - Returns: 복사가 일어났으면 true
    @discardableResult
    static func migrateLegacyStoreIfNeeded(from legacy: URL, to destination: URL) -> Bool {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path(percentEncoded: false)),
              fm.fileExists(atPath: legacy.path(percentEncoded: false)) else {
            return false
        }
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            for suffix in storeSuffixes {
                let source = sibling(of: legacy, suffix: suffix)
                guard fm.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
                try fm.copyItem(at: source, to: sibling(of: destination, suffix: suffix))
            }
            logger.info("히스토리 스토어를 앱 전용 폴더로 복사했습니다")
            return true
        } catch {
            logger.error("히스토리 스토어 이전 실패: \(error.localizedDescription)")
            removeStoreFiles(at: destination)
            return false
        }
    }

    /// 지정 위치에 컨테이너를 만든다. 열기에 실패하면 파일을 지우고 재생성하고,
    /// 그래도 실패하면 인메모리 컨테이너를 돌려준다 (히스토리 미저장).
    static func makeContainer(at url: URL) -> (container: ModelContainer, isInMemory: Bool) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = ModelConfiguration(url: url)

        do {
            return (try ModelContainer(for: TranslationRecord.self, configurations: config), false)
        } catch {
            logger.error("히스토리 스토어 열기 실패 — 파일을 지우고 재생성합니다: \(error.localizedDescription)")
        }

        removeStoreFiles(at: url)
        do {
            return (try ModelContainer(for: TranslationRecord.self, configurations: config), false)
        } catch {
            logger.fault("히스토리 스토어 재생성 실패 — 인메모리로 동작합니다 (히스토리 미저장): \(error.localizedDescription)")
        }

        let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        // 인메모리 컨테이너 생성은 스키마 자체가 깨진 경우에만 실패한다. 그 경우 앱을 계속 띄울 방법이 없다.
        let container = try! ModelContainer(for: TranslationRecord.self, configurations: memoryConfig)
        return (container, true)
    }

    private static func removeStoreFiles(at url: URL) {
        for suffix in storeSuffixes {
            try? FileManager.default.removeItem(at: sibling(of: url, suffix: suffix))
        }
    }

    /// `history.store` → `history.store-wal` 처럼 같은 폴더의 형제 파일 URL
    private static func sibling(of url: URL, suffix: String) -> URL {
        guard !suffix.isEmpty else { return url }
        return url.deletingLastPathComponent().appending(path: url.lastPathComponent + suffix)
    }
}
