import Foundation
import TideEnglishCore

/// Device-only settings, deliberately outside the learning archive and exports.
enum ModelSettings {
    private static let selectedKey = "tideenglish.model-provider.configuration.v1"
    private static func providerKey(_ provider: ModelProvider) -> String { selectedKey + "." + provider.rawValue }
    static func load() -> ProviderConfiguration {
        guard let stored = UserDefaults.standard.object(forKey: selectedKey) else {
            return ProviderConfiguration.restoreSelection(from: nil)
        }
        // A present value with the wrong stored type is corruption, never an absent legacy selection.
        return ProviderConfiguration.restoreSelection(from: stored as? Data ?? Data())
    }
    static func configuration(for provider: ModelProvider) -> ProviderConfiguration {
        decode(UserDefaults.standard.data(forKey: providerKey(provider))) ?? ProviderConfiguration(provider: provider)
    }
    static func save(_ configuration: ProviderConfiguration) throws {
        let value = try configuration.validated()
        let data = try JSONEncoder().encode(value)
        UserDefaults.standard.set(data, forKey: providerKey(value.provider))
        UserDefaults.standard.set(data, forKey: selectedKey)
    }
    private static func decode(_ data: Data?) -> ProviderConfiguration? {
        guard let data, let configuration = try? JSONDecoder().decode(ProviderConfiguration.self, from: data) else { return nil }
        return try? configuration.validated()
    }
}
