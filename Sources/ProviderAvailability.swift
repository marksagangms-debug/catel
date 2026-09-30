import Foundation

/// Read-only, local-only check for whether a provider has the credentials Catel needs.
/// Authentication and network errors are separate: a configured provider stays visible
/// when its API request is temporarily failing.
struct ProviderAvailability: Equatable {
    let values: [MenuBarProvider: Bool]

    init(values: [MenuBarProvider: Bool]) {
        self.values = values
    }

    subscript(provider: MenuBarProvider) -> Bool {
        values[provider] ?? false
    }

    var configuredProviders: [MenuBarProvider] {
        MenuBarProvider.realProviders.filter { self[$0] }
    }

    static func make(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        savedKeys: [CredentialProvider: String] = CredentialVault.shared.snapshot()
    ) -> ProviderAvailability {
        var values: [MenuBarProvider: Bool] = [:]

        values[.chatGPT] = validJSONCredential(
            at: homeDirectory.appendingPathComponent(".codex/auth.json"),
            providerKeys: ["tokens"]
        )
        values[.cursor] = cursorDatabaseExists(homeDirectory: homeDirectory)
        values[.hermes] = validJSONCredential(
            at: homeDirectory.appendingPathComponent(".hermes/auth.json"),
            providerKeys: ["providers", "nous"]
        )
        // A key pasted into Catel Settings counts the same as a local file, so
        // these providers work with Hermes/OpenCode absent.
        values[.openCode] = savedKeys[.openCode] != nil || validJSONCredential(
            at: homeDirectory.appendingPathComponent(".local/share/opencode/auth.json"),
            providerKeys: ["opencode-go"]
        )

        let env = homeDirectory.appendingPathComponent(".hermes/.env")
        let envValues = parseEnv(at: env)
        values[.deepSeek] = savedKeys[.deepSeek] != nil || envValues["DEEPSEEK_API_KEY"] != nil
        values[.commandCode] = savedKeys[.commandCode] != nil
            || envValues["COMMANDCODE_API_KEY"] != nil

        return ProviderAvailability(values: values)
    }

    /// Read-only check of the file Catel falls back to for a key-based provider,
    /// so Settings can show which source is in play.
    static func detectedLocally(
        _ provider: CredentialProvider,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        switch provider {
        case .deepSeek:
            return parseEnv(at: homeDirectory.appendingPathComponent(".hermes/.env"))["DEEPSEEK_API_KEY"] != nil
        case .commandCode:
            return parseEnv(at: homeDirectory.appendingPathComponent(".hermes/.env"))["COMMANDCODE_API_KEY"] != nil
        case .openCode:
            return validJSONCredential(
                at: homeDirectory.appendingPathComponent(".local/share/opencode/auth.json"),
                providerKeys: ["opencode-go"]
            )
        }
    }

    private static func validJSONCredential(at url: URL, providerKeys: [String]) -> Bool {
        guard
            let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        var current: Any? = root
        for key in providerKeys {
            current = (current as? [String: Any])?[key]
        }
        guard let dictionary = current as? [String: Any] else { return false }

        let tokenKeys = ["access_token", "accessToken", "agent_key", "key"]
        return tokenKeys.contains { stringValue(dictionary[$0]) != nil }
    }

    private static func cursorDatabaseExists(homeDirectory: URL) -> Bool {
        let paths = [
            "Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            "Library/Application Support/Cursor - Insiders/User/globalStorage/state.vscdb"
        ]
        return paths.contains {
            FileManager.default.fileExists(
                atPath: homeDirectory.appendingPathComponent($0).path
            )
        }
    }

    private static func parseEnv(at url: URL) -> [String: String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        var values: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let withoutExport = line.hasPrefix("export ")
                ? String(line.dropFirst("export ".count))
                : line
            guard let separator = withoutExport.firstIndex(of: "=") else { continue }

            let name = withoutExport[..<separator].trimmingCharacters(in: .whitespaces)
            var value = String(withoutExport[withoutExport.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value = String(value.dropFirst().dropLast())
            }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !trimmed.isEmpty {
                values[name] = trimmed
            }
        }
        return values
    }
}
