import Foundation

/// Catel's own key store: local-only, owner-only permissions, and a saved key
/// that overrides the vendor file Catel would otherwise read.
@main
enum CredentialVaultTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CredentialVaultTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("Catel/credentials.json")
        let vault = CredentialVault(url: url)

        // Nothing saved yet.
        precondition(vault.key(for: .deepSeek) == nil)
        precondition(vault.hasKey(for: .deepSeek) == false)
        precondition(vault.savedCount == 0)
        precondition(FileManager.default.fileExists(atPath: url.path) == false)

        // Saving trims, persists, and locks the file down.
        try vault.setKey("  sk-deepseek-secret  \n", for: .deepSeek)
        precondition(vault.key(for: .deepSeek) == "sk-deepseek-secret")
        precondition(vault.hasKey(for: .deepSeek) == true)

        let filePermissions = try permissions(of: url)
        precondition(filePermissions == 0o600, "expected 0600, got \(String(filePermissions, radix: 8))")
        let directoryPermissions = try permissions(of: root.appendingPathComponent("Catel"))
        precondition(
            directoryPermissions == 0o700,
            "expected 0700, got \(String(directoryPermissions, radix: 8))"
        )

        let contents = try String(contentsOf: url, encoding: .utf8)
        precondition(contents.contains("\"deepSeek\""))
        precondition(contents.contains("sk-deepseek-secret"))

        // A second instance (fresh process equivalent) reads the same file.
        let reloaded = CredentialVault(url: url)
        precondition(reloaded.key(for: .deepSeek) == "sk-deepseek-secret")
        precondition(reloaded.key(for: .commandCode) == nil)
        precondition(reloaded.savedCount == 1)
        precondition(reloaded.snapshot()[.deepSeek] == "sk-deepseek-secret")

        // Two providers coexist.
        try reloaded.setKey("cc-secret", for: .commandCode)
        precondition(reloaded.savedCount == 2)
        precondition(CredentialVault(url: url).key(for: .commandCode) == "cc-secret")

        // A blank key clears instead of storing whitespace.
        try reloaded.setKey("   ", for: .openCode)
        precondition(reloaded.hasKey(for: .openCode) == false)

        // Clearing the last key removes the file rather than leaving an empty one.
        try reloaded.clear(.deepSeek)
        precondition(reloaded.hasKey(for: .deepSeek) == false)
        precondition(reloaded.savedCount == 1)
        try reloaded.clear(.commandCode)
        precondition(reloaded.savedCount == 0)
        precondition(FileManager.default.fileExists(atPath: url.path) == false)

        print("CredentialVaultTests: PASS")
    }

    private static func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let value = attributes[.posixPermissions] as? NSNumber
        return value?.intValue ?? -1
    }
}
