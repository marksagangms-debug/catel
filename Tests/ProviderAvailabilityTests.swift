import Foundation

@main
enum ProviderAvailabilityTests {
    static func main() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProviderAvailabilityTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }

        // `savedKeys` is always injected: the real vault on the machine running
        // the tests must not leak into these assertions.
        func availabilityWith(_ keys: [CredentialProvider: String] = [:]) -> ProviderAvailability {
            ProviderAvailability.make(homeDirectory: home, savedKeys: keys)
        }

        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".hermes"),
            withIntermediateDirectories: true
        )
        let env = home.appendingPathComponent(".hermes/.env")
        try "DEEPSEEK_API_KEY=secret\n".write(to: env, atomically: true, encoding: .utf8)

        let availability = availabilityWith()
        precondition(availability[.chatGPT] == false)
        precondition(availability[.cursor] == false)
        precondition(availability[.hermes] == false)
        precondition(availability[.deepSeek] == true)
        precondition(availability[.openCode] == false)
        precondition(availability[.commandCode] == false)

        try "DEEPSEEK_API_KEY=secret\nCOMMANDCODE_API_KEY=secret\n".write(
            to: env,
            atomically: true,
            encoding: .utf8
        )
        precondition(availabilityWith()[.deepSeek] == true)
        precondition(availabilityWith()[.commandCode] == true)

        let codexDirectory = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try #"{"tokens":{"access_token":"secret"}}"#.write(
            to: codexDirectory.appendingPathComponent("auth.json"),
            atomically: true,
            encoding: .utf8
        )
        precondition(availabilityWith()[.chatGPT] == true)

        let cursorDirectory = home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage")
        try FileManager.default.createDirectory(at: cursorDirectory, withIntermediateDirectories: true)
        try Data().write(to: cursorDirectory.appendingPathComponent("state.vscdb"))
        precondition(availabilityWith()[.cursor] == true)

        let hermesAuth = home.appendingPathComponent(".hermes/auth.json")
        try #"{"providers":{"nous":{"access_token":"secret"}}}"#.write(
            to: hermesAuth,
            atomically: true,
            encoding: .utf8
        )
        precondition(availabilityWith()[.hermes] == true)

        let openCodeDirectory = home.appendingPathComponent(".local/share/opencode")
        try FileManager.default.createDirectory(at: openCodeDirectory, withIntermediateDirectories: true)
        try #"{"opencode-go":{"key":"secret"}}"#.write(
            to: openCodeDirectory.appendingPathComponent("auth.json"),
            atomically: true,
            encoding: .utf8
        )
        precondition(availabilityWith()[.openCode] == true)

        try "DEEPSEEK_API_KEY=\n".write(to: env, atomically: true, encoding: .utf8)
        precondition(availabilityWith()[.deepSeek] == false)

        // Detected-source helper used by the Settings panel mirrors the files.
        // The env file now holds only an empty DEEPSEEK_API_KEY, so both keys
        // that live there read as absent; the OpenCode file is untouched.
        precondition(ProviderAvailability.detectedLocally(.deepSeek, homeDirectory: home) == false)
        precondition(ProviderAvailability.detectedLocally(.commandCode, homeDirectory: home) == false)
        precondition(ProviderAvailability.detectedLocally(.openCode, homeDirectory: home) == true)

        // A key saved in Catel Settings is enough on its own: no vendor file, no
        // Hermes, and the provider is still configured.
        let bareHome = home.appendingPathComponent("bare")
        try FileManager.default.createDirectory(at: bareHome, withIntermediateDirectories: true)

        let saved: [CredentialProvider: String] = [
            .deepSeek: "saved-deepseek",
            .commandCode: "saved-commandcode",
            .openCode: "saved-opencode",
        ]
        let fromSettings = ProviderAvailability.make(homeDirectory: bareHome, savedKeys: saved)
        precondition(fromSettings[.deepSeek] == true)
        precondition(fromSettings[.commandCode] == true)
        precondition(fromSettings[.openCode] == true)
        precondition(fromSettings[.hermes] == false)
        precondition(fromSettings[.chatGPT] == false)

        let empty = ProviderAvailability.make(homeDirectory: bareHome, savedKeys: [:])
        precondition(empty[.deepSeek] == false)
        precondition(empty[.openCode] == false)
        precondition(empty.configuredProviders.isEmpty)

        // Clearing the saved key falls back to the vendor file.
        let mixed = ProviderAvailability.make(homeDirectory: home, savedKeys: [.deepSeek: "saved"])
        precondition(mixed[.deepSeek] == true)

        print("ProviderAvailabilityTests: PASS")
    }
}
