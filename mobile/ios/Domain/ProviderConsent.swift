import Foundation

/// Stored learning consent must authorize the actual model recipient.
public enum ProviderConsent {
    public static func identity(for configuration: ProviderConfiguration) throws -> String {
        let value = try configuration.validated()
        return value.provider.rawValue + "|" + value.baseURL + "|" + value.model
    }
    public static func isAllowed(configuration: ProviderConfiguration, version: Int?, requiredVersion: Int,
                                 acceptedIdentity: String?) -> Bool {
        guard version == requiredVersion, let identity = try? identity(for: configuration) else { return false }
        if let acceptedIdentity { return identity == acceptedIdentity }
        // The installed build's consent named OpenAI explicitly. Preserve that recipient only.
        return configuration.provider == .openAI
    }
}
