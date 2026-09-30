import AppKit
import SwiftUI

/// Result of a key check in Settings: the provider's own client runs against the
/// key that is currently in effect (saved key first, detected file second).
enum KeyTestState: Equatable {
    case running
    case passed(String)
    case failed(String)
}

/// Settings panel: paste a provider API key to run Catel without another tool's
/// login. Saved keys live only in `CredentialVault`; the read-only providers
/// keep reading their local files, so the Hermes connection is untouched.
struct CatelSettingsView: View {
    let monitor: UsageMonitor
    let vault: CredentialVault
    let onClose: () -> Void

    @State private var drafts: [CredentialProvider: String] = [:]
    @State private var savedKeys: Set<CredentialProvider> = []
    @State private var detectedKeys: [CredentialProvider: Bool] = [:]
    @State private var tests: [CredentialProvider: KeyTestState] = [:]
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            keySection
            divider
            readOnlySection
            divider
            footer
        }
        .padding(18)
        .frame(width: 460)
        .onAppear(perform: refreshLocalState)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Provider API keys")
                .font(.system(size: CatelToken.titleFontSize, weight: .semibold))
                .foregroundStyle(CatelToken.textPrimary)

            Text("Paste a key to fetch that provider's usage directly. A saved key is used instead of the local file Catel would otherwise read, so Hermes does not have to be configured. Keys stay on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(CatelToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(CredentialProvider.allCases) { provider in
                keyRow(provider)
                if provider != CredentialProvider.allCases.last {
                    Rectangle()
                        .fill(CatelToken.divider)
                        .frame(height: 1)
                }
            }

            if let saveError {
                Text(saveError)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .systemRed))
            }
        }
    }

    private func keyRow(_ provider: CredentialProvider) -> some View {
        let isSaved = savedKeys.contains(provider)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(provider.title)
                    .font(.system(size: CatelToken.fieldFontSize, weight: .semibold))
                    .foregroundStyle(CatelToken.textPrimary)

                Spacer(minLength: 8)

                statusBadge(provider, isSaved: isSaved)
            }

            HStack(spacing: 8) {
                SecureField(
                    isSaved ? "Replace saved key" : "Paste \(provider.title) API key",
                    text: draftBinding(provider)
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .onSubmit { save(provider) }

                Button("Save") { save(provider) }
                    .disabled(trimmedDraft(provider).isEmpty)

                Button("Test") { runTest(provider) }
                    .disabled(!isSaved && detectedKeys[provider] != true)

                if isSaved {
                    Button("Clear") { clear(provider) }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Falls back to \(provider.fallbackSource) · \(provider.keyName)")
                    .font(.system(size: CatelToken.microFontSize))
                    .foregroundStyle(CatelToken.textSecondary)

                Spacer(minLength: 4)

                testCaption(provider)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ provider: CredentialProvider, isSaved: Bool) -> some View {
        if isSaved {
            badge("Saved in Catel", color: Color(nsColor: .systemGreen))
        } else if detectedKeys[provider] == true {
            badge("Using \(provider.fallbackSource)", color: CatelToken.textSecondary)
        } else {
            badge("Not set", color: CatelToken.textSecondary)
        }
    }

    @ViewBuilder
    private func testCaption(_ provider: CredentialProvider) -> some View {
        switch tests[provider] {
        case .running:
            Text("Checking…")
                .font(.system(size: CatelToken.microFontSize))
                .foregroundStyle(CatelToken.textSecondary)
        case .passed(let detail):
            Text("Key works · \(detail)")
                .font(.system(size: CatelToken.microFontSize))
                .foregroundStyle(Color(nsColor: .systemGreen))
        case .failed(let message):
            Text(message)
                .font(.system(size: CatelToken.microFontSize))
                .foregroundStyle(Color(nsColor: .systemRed))
        case nil:
            EmptyView()
        }
    }

    /// Providers Catel still reads from another app (no key entry): the Nous
    /// entry is deliberately part of that list, because its refresh token is
    /// single-use and refreshing it from Catel would sign Hermes out.
    private var readOnlySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Read-only from other apps")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(CatelToken.textSecondary)

            ForEach(ReadOnlyCredentialSource.providers) { provider in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(provider.title)
                        .font(.system(size: CatelToken.fieldFontSize, weight: .medium))
                        .foregroundStyle(CatelToken.textPrimary)

                    Text(ReadOnlyCredentialSource.describe(provider) ?? "")
                        .font(.system(size: CatelToken.microFontSize))
                        .foregroundStyle(CatelToken.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if monitor.isAvailable(provider) {
                        badge("Detected", color: Color(nsColor: .systemGreen))
                    } else {
                        badge("Not found", color: CatelToken.textSecondary)
                    }
                }
            }

            Text("Nous keeps using your local Hermes session: Portal refresh tokens are single-use, so Catel only reads the token Hermes already wrote.")
                .font(.system(size: CatelToken.microFontSize))
                .foregroundStyle(CatelToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved keys live at \(displayPath) with owner-only permissions (0600). Nothing is synced or uploaded, and Catel never writes another app's credential files.")
                .font(.system(size: CatelToken.microFontSize))
                .foregroundStyle(CatelToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer(minLength: 0)
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(CatelToken.divider)
            .frame(height: 1)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: CatelToken.tagFontSize, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    // MARK: - State

    private func draftBinding(_ provider: CredentialProvider) -> Binding<String> {
        Binding(
            get: { drafts[provider] ?? "" },
            set: { drafts[provider] = $0 }
        )
    }

    private func trimmedDraft(_ provider: CredentialProvider) -> String {
        (drafts[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshLocalState() {
        savedKeys = Set(CredentialProvider.allCases.filter { vault.hasKey(for: $0) })
        detectedKeys = Dictionary(
            uniqueKeysWithValues: CredentialProvider.allCases.map {
                ($0, ProviderAvailability.detectedLocally($0))
            }
        )
    }

    private func save(_ provider: CredentialProvider) {
        let draft = trimmedDraft(provider)
        guard !draft.isEmpty else { return }

        do {
            try vault.setKey(draft, for: provider)
            drafts[provider] = ""
            saveError = nil
            refreshLocalState()
            monitor.refreshProviderAvailability()
            monitor.refresh()
            runTest(provider)
        } catch {
            saveError = "Could not save the key: \(error.localizedDescription)"
        }
    }

    private func clear(_ provider: CredentialProvider) {
        do {
            try vault.clear(provider)
            drafts[provider] = ""
            saveError = nil
            tests[provider] = nil
            refreshLocalState()
            monitor.refreshProviderAvailability()
            monitor.refresh()
        } catch {
            saveError = "Could not clear the key: \(error.localizedDescription)"
        }
    }

    private func runTest(_ provider: CredentialProvider) {
        tests[provider] = .running

        let finish: (Result<String, UsageClientError>) -> Void = { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let detail):
                    tests[provider] = .passed(detail)
                case .failure(let error):
                    tests[provider] = .failed(error.message)
                }
            }
        }

        switch provider {
        case .deepSeek:
            DeepSeekUsageClient.fetch { result in
                finish(result.map {
                    "balance \(formatBalance($0.totalBalance, currency: $0.currency))"
                })
            }
        case .commandCode:
            CommandCodeUsageClient.fetch { result in
                finish(result.map { usage in
                    usage.planName.map { "\($0) plan" } ?? "rolling caps"
                })
            }
        case .openCode:
            OpenCodeUsageClient.fetch { result in
                finish(result.map { usage in
                    usage.rolling.map { "5-hour \(formatPercent($0.usedPercent))" } ?? "limits"
                })
            }
        }
    }

    private var displayPath: String {
        let path = vault.storageURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - Window

final class SettingsWindowController: NSWindowController {
    convenience init(monitor: UsageMonitor, vault: CredentialVault = .shared) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Catel Settings"
        window.isReleasedWhenClosed = false
        window.center()

        let hostingView = NSHostingView(
            rootView: CatelSettingsView(monitor: monitor, vault: vault) { [weak window] in
                window?.close()
            }
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        let fitted = hostingView.fittingSize
        if fitted.height > 0 {
            window.setContentSize(NSSize(width: 460, height: fitted.height))
        }

        self.init(window: window)
    }
}
