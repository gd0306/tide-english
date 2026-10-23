import Foundation
import SwiftData
import Security
import Observation
import TideEnglishCore

@Model final class StoredArchive {
    @Attribute(.unique) var key: String
    var payload: Data
    init(payload: Data) { key = "tideenglish-v1"; self.payload = payload }
}

@MainActor @Observable final class LearningStore {
    private(set) var archive = Archive()
    var error: String?
    @ObservationIgnored var onSessionInvalidation: ((UUID) -> Void)?
    @ObservationIgnored var onVocabularyContextChange: (() -> Void)?
    @ObservationIgnored var onVocabularyErase: (() -> Void)?
    @ObservationIgnored private(set) var vocabularyCache = VocabularyCache()
    private(set) var vocabularyCacheError: String?
    private let vocabularyCacheURL: URL?
    let container: ModelContainer
    private var document: StoredArchive
    private let migrationBackupURL: URL?
    init(inMemory: Bool = false) throws {
        vocabularyCacheURL = inMemory ? nil : URL.applicationSupportDirectory
            .appendingPathComponent("Tide English", isDirectory: true)
            .appendingPathComponent("vocabulary-definitions-v1.json")
        if let url = vocabularyCacheURL,
           let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size <= 4 * 1024 * 1024,
           let data = try? Data(contentsOf: url), let cache = try? VocabularyCache.decode(data) {
            vocabularyCache = cache
        }
        migrationBackupURL = inMemory ? nil : URL.applicationSupportDirectory
            .appendingPathComponent("Tide English", isDirectory: true)
            .appendingPathComponent("before-language-modules.json")
        container = try ModelContainer(for: StoredArchive.self, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none))
        let context = container.mainContext
        if let existing = try context.fetch(FetchDescriptor<StoredArchive>()).first {
            document = existing
            archive = try Archive.decode(existing.payload)
            if let backup = migrationBackupURL,
               let root = try JSONSerialization.jsonObject(with: existing.payload) as? [String: Any], root["schemaVersion"] as? Int == 1 {
                let directory = backup.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try existing.payload.write(to: backup, options: [.atomic, .completeFileProtection])
                }
            }
            for i in archive.sessions.indices where archive.sessions[i].endedAt == nil {
                archive.sessions[i].endedAt = .now; archive.sessions[i].endReason = "App closed before finalization"
            }
        } else {
            document = StoredArchive(payload: try Archive().encoded()); context.insert(document)
        }
        persist()
    }
    var preferences: Preferences { archive.preferences }
    var language: LanguageModule { LanguageRegistry.module(for: preferences.learningLanguageID)! }
    var sessions: [SessionRecord] { archive.sessions.sorted { $0.startedAt > $1.startedAt } }
    var learningSessions: [SessionRecord] { sessions.filter { $0.languageID == language.id } }
    var learner: LearnerState { LearningEngine.project(archive.sessions, languageID: language.id, hiddenWords: archive.preferences.hiddenWords) }
    func selectLanguage(_ id: String) {
        guard LanguageRegistry.module(for: id) != nil else { return }
        archive.preferences.learningLanguageID = id; persist()
    }
    func updatePreferences(_ change: (inout Preferences) -> Void) { change(&archive.preferences); persist() }
    func save(_ session: SessionRecord) {
        if let i = archive.sessions.firstIndex(where: { $0.id == session.id }) { archive.sessions[i] = session }
        else { archive.sessions.append(session) }
        persist()
    }
    func deleteSession(_ id: UUID) { onSessionInvalidation?(id); archive.sessions.removeAll { $0.id == id }; persist() }
    func hideWord(_ id: String) { archive.preferences.hiddenWords.append(id); persist() }
    func correctPassage(sessionID: UUID, passageID: String, text: String) {
        guard let index = archive.sessions.firstIndex(where: { $0.id == sessionID }),
              let passage = archive.sessions[index].passages.first(where: { $0.id == passageID && $0.speaker == .user }) else { return }
        for (offset, fragment) in passage.fragments.enumerated() {
            archive.sessions[index].correctFragment(id: fragment.id, text: offset == 0 ? String(text.prefix(10_000)) : "")
        }
        onSessionInvalidation?(sessionID)
        persist()
    }
    func deleteAll() {
        if let migrationBackupURL {
            do { try FileManager.default.removeItem(at: migrationBackupURL) }
            catch CocoaError.fileNoSuchFile { /* Most installations have no migration backup. */ }
            catch {
                self.error = "Tide English couldn’t delete the older learning backup. Your conversations are still here. Please try again."
                return
            }
        }
        archive.sessions.forEach { onSessionInvalidation?($0.id) }
        if let vocabularyCacheURL {
            do { try FileManager.default.removeItem(at: vocabularyCacheURL) }
            catch CocoaError.fileNoSuchFile { }
            catch {
                self.error = "Saved definitions couldn’t be deleted. Your learning data is still here. Please try again."
                return
            }
        }
        vocabularyCache.removeAll(); vocabularyCacheError = nil
        onVocabularyErase?()
        archive.sessions = []; archive.preferences.hiddenWords = []; persist()
    }
    func exportData() throws -> Data { try archive.encoded() }
    func importData(_ data: Data) throws {
        let imported = try Archive.decode(data)
        archive = try archive.merging(imported)
        persist()
    }
    func saveVocabularyCache(_ cache: VocabularyCache) {
        vocabularyCache = cache
        guard let url = vocabularyCacheURL else { return }
        do {
            let data = try cache.encoded()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            vocabularyCacheError = nil
        } catch {
            vocabularyCacheError = "Definitions are available now but couldn’t be saved for next time."
        }
    }
    private func persist() {
        onVocabularyContextChange?()
        do { document.payload = try archive.encoded(); try container.mainContext.save(); error = nil }
        catch { self.error = "Tide English couldn’t save your progress. Please export a backup and try again." }
    }
}

enum CredentialStore {
    private static func query(configuration: ProviderConfiguration) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: try configuration.credentialService(),
         kSecAttrAccount as String: "owner", kSecAttrSynchronizable as String: false]
    }
    // Legacy methods retain the installed OpenAI service/account.
    static func read() -> String? { read(configuration: .init(provider: .openAI)) }
    static var hasKey: Bool { hasKey(configuration: .init(provider: .openAI)) }
    static func save(_ key: String) throws { try save(key, configuration: .init(provider: .openAI)) }
    static func delete() throws { try delete(configuration: .init(provider: .openAI)) }
    static func read(configuration: ProviderConfiguration) -> String? {
        guard var q = try? query(configuration: configuration) else { return nil }
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func hasKey(configuration: ProviderConfiguration) -> Bool {
        guard var q = try? query(configuration: configuration) else { return false }
        // Presence must never retrieve or decode the secret.
        q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }
    static func save(_ key: String, configuration: ProviderConfiguration) throws {
        let value = try ProviderConfiguration.validatedCredential(key)
        let q = try query(configuration: configuration)
        let data = Data(value.utf8)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = q; insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw KeyError.save }
        } else if status != errSecSuccess { throw KeyError.save }
    }
    static func delete(configuration: ProviderConfiguration) throws {
        let status = SecItemDelete(try query(configuration: configuration) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError.remove }
    }
    enum KeyError: LocalizedError {
        case invalid, save, remove
        var errorDescription: String? {
            switch self {
            case .invalid: "Enter a valid API key."
            case .save: "The key couldn’t be saved to this device’s Keychain."
            case .remove: "The key couldn’t be removed. Unlock this iPhone and try again."
            }
        }
    }
}
