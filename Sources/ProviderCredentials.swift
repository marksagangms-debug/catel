import Foundation

/// Providers whose usage API is authenticated with a plain API key the user can
/// paste into Catel Settings. The other providers stay read-only from the app
/// that owns their session: ChatGPT and Nous need OAuth access tokens that only
/// Codex/Hermes can mint (Nous refresh tokens are single-use), and Cursor needs
/// its dashboard session token.
enum CredentialProvider: String, CaseIterable, Identifiable {
    case deepSeek
    case commandCode
    case openCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .commandCode: return "CommandCode"
        case .openCode: return "OpenCode Go"
        }
    }

    /// Provider this key feeds, for availability and status lookups.
    var menuBarProvider: MenuBarProvider {
        switch self {
        case .deepSeek: return .deepSeek
        case .commandCode: return .commandCode
        case .openCode: return .openCode
        }
    }

    /// Name the vendor tool uses for the same key, shown in Settings.
    var keyName: String {
        switch self {
        case .deepSeek: return "DEEPSEEK_API_KEY"
        case .commandCode: return "COMMANDCODE_API_KEY"
        case .openCode: return "opencode-go key"
        }
    }

    /// Where Catel reads this key when nothing is saved in Settings.
    var fallbackSource: String {
        switch self {
        case .deepSeek, .commandCode: return "~/.hermes/.env"
        case .openCode: return "~/.local/share/opencode/auth.json"
        }
    }
}

/// Local-only store for API keys typed into Catel Settings.
///
/// A saved key always wins over the vendor file Catel would otherwise read, so
/// the provider works without Hermes, Codex, or OpenCode installed.
///
/// The file is `~/Library/Application Support/Catel/credentials.json`, written
/// with `0600` inside a `0700` directory. It never leaves this Mac: nothing here
/// is synced, uploaded, or logged, and Catel still never writes another app's
/// credential files.
final class CredentialVault {
    static let shared = CredentialVault()

    static var defaultURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Catel", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private let url: URL
    private let lock = NSLock()
    private var cache: [CredentialProvider: String]?

    init(url: URL = CredentialVault.defaultURL) {
        self.url = url
    }

    var storageURL: URL { url }

    func key(for provider: CredentialProvider) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return contentsLocked()[provider]
    }

    func hasKey(for provider: CredentialProvider) -> Bool {
        key(for: provider) != nil
    }

    /// A copy of every saved key, for availability checks on other threads.
    func snapshot() -> [CredentialProvider: String] {
        lock.lock()
        defer { lock.unlock() }
        return contentsLocked()
    }

    var savedCount: Int { snapshot().count }

    /// Saves one provider's key. A nil or blank key clears it.
    func setKey(_ key: String?, for provider: CredentialProvider) throws {
        lock.lock()
        defer { lock.unlock() }

        var values = contentsLocked()
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            values[provider] = nil
        } else {
            values[provider] = trimmed
        }

        try persist(values)
        cache = values
    }

    func clear(_ provider: CredentialProvider) throws {
        try setKey(nil, for: provider)
    }

    // MARK: - Storage

    private func contentsLocked() -> [CredentialProvider: String] {
        if let cache { return cache }
        let loaded = Self.read(from: url)
        cache = loaded
        return loaded
    }

    private func persist(_ values: [CredentialProvider: String]) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()

        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        guard !values.isEmpty else {
            if manager.fileExists(atPath: url.path) {
                try manager.removeItem(at: url)
            }
            return
        }

        var payload: [String: String] = [:]
        for (provider, key) in values {
            payload[provider.rawValue] = key
        }

        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        // `.atomic` replaces the file, so re-apply the restrictive mode after.
        try data.write(to: url, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func read(from url: URL) -> [CredentialProvider: String] {
        guard
            let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var values: [CredentialProvider: String] = [:]
        for (rawProvider, rawKey) in root {
            guard
                let provider = CredentialProvider(rawValue: rawProvider),
                let key = rawKey as? String,
                !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            values[provider] = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return values
    }
}

/// Names of the read-only providers, for the Settings panel's detection list.
enum ReadOnlyCredentialSource {
    static func describe(_ provider: MenuBarProvider) -> String? {
        switch provider {
        case .chatGPT: return "~/.codex/auth.json"
        case .cursor: return "Cursor app data (state.vscdb)"
        case .hermes: return "~/.hermes/auth.json"
        case .deepSeek, .openCode, .commandCode, .none: return nil
        }
    }

    static var providers: [MenuBarProvider] {
        MenuBarProvider.realProviders.filter { describe($0) != nil }
    }
}
