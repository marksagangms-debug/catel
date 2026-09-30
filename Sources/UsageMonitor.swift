import Foundation
import SwiftUI

enum UsageClientError: Error {
    case missingCredentials(String)
    case authentication
    case network
    case invalidResponse
    case unavailable(String)

    var message: String {
        switch self {
        case .missingCredentials(let message):
            return message
        case .authentication:
            return "Sign in again to refresh"
        case .network:
            return "Network unavailable"
        case .invalidResponse:
            return "Usage data unavailable"
        case .unavailable(let message):
            return message
        }
    }
}

enum ProviderStatus: Equatable {
    case loading
    case ready
    case stale(String)
    case unavailable(String)

    var message: String? {
        switch self {
        case .loading, .ready:
            return nil
        case .stale(let message), .unavailable(let message):
            return message
        }
    }
}

struct UsageWindow: Equatable {
    let usedPercent: Double
    let resetAt: Date?
    let windowSeconds: Double?
}

struct ChatGPTUsage: Equatable {
    let planName: String?
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?
}

struct CursorUsage: Equatable {
    let planName: String?
    let usedDollars: Double
    let limitDollars: Double
    let cursorModelsPercentUsed: Double?
    let otherModelsPercentUsed: Double?
    let percentUsed: Double
    let billingCycleEnd: Date?
}

func formatBalance(_ amount: Double, currency: String) -> String {
    let symbol = currency.uppercased() == "USD" ? "$" : ""
    return symbol.isEmpty
        ? String(format: "%.2f %@", max(amount, 0), currency.uppercased())
        : String(format: "%@%.2f", symbol, max(amount, 0))
}

func formatResetCaption(_ date: Date?) -> String {
    formatReset(date) ?? "unavailable"
}

func formatCycleCaption(_ date: Date?) -> String? {
    formatReset(date)
}

enum ChatGPTSessionWindow: String, CaseIterable, Identifiable {
    case fiveHour
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHour: return "5-hour"
        case .weekly: return "7-day"
        }
    }

    var shortTitle: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "W"
        }
    }

    func window(from usage: ChatGPTUsage?) -> UsageWindow? {
        guard let usage else { return nil }
        switch self {
        case .fiveHour: return usage.primaryWindow
        case .weekly: return usage.secondaryWindow
        }
    }

    func percent(from usage: ChatGPTUsage?) -> Double? {
        window(from: usage)?.usedPercent
    }

    func percent(from usage: ChatGPTUsage?, preference: ChatGPTSessionWindow) -> Double? {
        preference.percent(from: usage)
            ?? Self.fiveHour.percent(from: usage)
            ?? Self.weekly.percent(from: usage)
    }
}

enum UsageWindowMetric: String, CaseIterable, Identifiable {
    case fiveHour
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHour: return "5-hour"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var shortTitle: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "W"
        case .monthly: return "M"
        }
    }

    func window(from usage: OpenCodeUsage?) -> UsageWindow? {
        guard let usage else { return nil }
        switch self {
        case .fiveHour: return usage.rolling
        case .weekly: return usage.weekly
        case .monthly: return usage.monthly
        }
    }

    func window(from usage: CommandCodeUsage?) -> UsageWindow? {
        guard let usage else { return nil }
        switch self {
        case .fiveHour: return usage.fiveHour
        case .weekly: return usage.weekly
        case .monthly: return usage.monthly
        }
    }

    func percent(from usage: OpenCodeUsage?) -> Double? {
        window(from: usage)?.usedPercent
    }

    func percent(from usage: CommandCodeUsage?) -> Double? {
        window(from: usage)?.usedPercent
    }

    /// Prefer the chosen window, then use the provider's first available window.
    func percent(from usage: OpenCodeUsage?, preference: UsageWindowMetric) -> Double? {
        preference.percent(from: usage)
            ?? Self.fiveHour.percent(from: usage)
            ?? Self.weekly.percent(from: usage)
            ?? Self.monthly.percent(from: usage)
    }

    func percent(from usage: CommandCodeUsage?, preference: UsageWindowMetric) -> Double? {
        preference.percent(from: usage)
            ?? Self.fiveHour.percent(from: usage)
            ?? Self.weekly.percent(from: usage)
            ?? Self.monthly.percent(from: usage)
    }
}

enum CursorStatusMetric: String, CaseIterable, Identifiable {
    case cursorModels
    case otherModels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursorModels:
            return "Cursor Models"
        case .otherModels:
            return "Other Models"
        }
    }

    var shortTitle: String {
        switch self {
        case .cursorModels:
            return "Cursor"
        case .otherModels:
            return "Other"
        }
    }

    func percent(from usage: CursorUsage?) -> Double? {
        switch self {
        case .cursorModels:
            return usage?.cursorModelsPercentUsed
        case .otherModels:
            return usage?.otherModelsPercentUsed ?? usage?.percentUsed
        }
    }
}

func numericValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        return number.doubleValue
    }

    if let string = value as? String {
        return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return nil
}

func stringValue(_ value: Any?) -> String? {
    guard let string = value as? String else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func dateValue(_ value: Any?) -> Date? {
    if let timestamp = numericValue(value) {
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
        return Date(timeIntervalSince1970: seconds)
    }

    guard let string = stringValue(value) else { return nil }
    if let timestamp = Double(string) {
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
        return Date(timeIntervalSince1970: seconds)
    }

    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: string) {
        return date
    }

    formatter.formatOptions.insert(.withFractionalSeconds)
    return formatter.date(from: string)
}

func formatPercent(_ percent: Double) -> String {
    let bounded = min(max(percent, 0), 100)
    return String(format: "%.0f%%", bounded)
}

func formatDollars(_ dollars: Double) -> String {
    return String(format: "$%.2f", max(dollars, 0))
}

func formatReset(_ date: Date?) -> String? {
    guard let date else { return nil }

    let remaining = Int(date.timeIntervalSinceNow.rounded())
    if remaining <= 0 {
        return "resetting"
    }

    if remaining >= 86_400 {
        return "\(remaining / 86_400)d \(remaining / 3_600 % 24)h"
    }
    if remaining >= 3_600 {
        return "\(remaining / 3_600)h \(remaining / 60 % 60)m"
    }
    return "\(max(remaining / 60, 1))m"
}

final class UsageMonitor: ObservableObject {
    private static let cursorStatusMetricKey = "cursorStatusMetric"
    private static let chatGPTStatusMetricKey = "chatGPTStatusMetric"
    private static let openCodeStatusMetricKey = "openCodeStatusMetric"
    private static let commandCodeStatusMetricKey = "commandCodeStatusMetric"
    private static let menuBarSlotsKey = "menuBarSlots"

    static let menuBarSlotCount = 3

    @Published private(set) var chatGPTUsage: ChatGPTUsage?
    @Published private(set) var cursorUsage: CursorUsage?
    @Published private(set) var hermesUsage: HermesUsage?
    @Published private(set) var deepSeekUsage: DeepSeekUsage?
    @Published private(set) var openCodeUsage: OpenCodeUsage?
    @Published private(set) var commandCodeUsage: CommandCodeUsage?
    @Published private(set) var chatGPTStatus: ProviderStatus = .loading
    @Published private(set) var cursorStatus: ProviderStatus = .loading
    @Published private(set) var hermesStatus: ProviderStatus = .loading
    @Published private(set) var deepSeekStatus: ProviderStatus = .loading
    @Published private(set) var openCodeStatus: ProviderStatus = .loading
    @Published private(set) var commandCodeStatus: ProviderStatus = .loading
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var cursorStatusMetric: CursorStatusMetric
    @Published private(set) var chatGPTStatusMetric: ChatGPTSessionWindow
    @Published private(set) var openCodeStatusMetric: UsageWindowMetric
    @Published private(set) var commandCodeStatusMetric: UsageWindowMetric
    /// Providers with readable local credentials. Missing providers stay in the
    /// configuration, but are hidden from both the detail popover and slot menus.
    @Published private(set) var providerAvailability: ProviderAvailability
    /// Exactly `menuBarSlotCount` providers, in display order, drive the menu-bar title.
    @Published private(set) var menuBarSlots: [MenuBarProvider]

    var onChange: (() -> Void)?
    var providerAvailabilityDidChange: (() -> Void)?

    private var timer: Timer?
    private var pendingRequests = 0

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.cursorStatusMetricKey),
           let metric = CursorStatusMetric(rawValue: raw) {
            cursorStatusMetric = metric
        } else {
            cursorStatusMetric = .otherModels
        }

        if let raw = UserDefaults.standard.string(forKey: Self.chatGPTStatusMetricKey),
           let metric = ChatGPTSessionWindow(rawValue: raw) {
            chatGPTStatusMetric = metric
        } else {
            chatGPTStatusMetric = .fiveHour
        }

        openCodeStatusMetric = Self.loadWindowMetric(
            key: Self.openCodeStatusMetricKey,
            fallback: .fiveHour
        )
        commandCodeStatusMetric = Self.loadWindowMetric(
            key: Self.commandCodeStatusMetricKey,
            fallback: .fiveHour
        )

        providerAvailability = ProviderAvailability.make()
        menuBarSlots = Self.loadMenuBarSlots()

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    var availableProviders: [MenuBarProvider] {
        providerAvailability.configuredProviders
    }

    func isAvailable(_ provider: MenuBarProvider) -> Bool {
        providerAvailability[provider]
    }

    var visibleMenuBarProviders: [MenuBarProvider] {
        VisibleMenuBarProviders.resolve(
            slots: menuBarSlots,
            availability: providerAvailability
        )
    }

    func refreshProviderAvailability() {
        let updated = ProviderAvailability.make()
        guard updated.values != providerAvailability.values else { return }
        providerAvailability = updated
        providerAvailabilityDidChange?()
        onChange?()
    }

    private static func loadWindowMetric(
        key: String,
        fallback: UsageWindowMetric
    ) -> UsageWindowMetric {
        guard
            let raw = UserDefaults.standard.string(forKey: key),
            let metric = UsageWindowMetric(rawValue: raw)
        else { return fallback }
        return metric
    }

    private static func loadMenuBarSlots() -> [MenuBarProvider] {
        let fallback: [MenuBarProvider] = [.chatGPT, .cursor, .hermes]

        guard let raw = UserDefaults.standard.array(forKey: menuBarSlotsKey) as? [String] else {
            return fallback
        }

        var slots: [MenuBarProvider] = []
        var hiddenCount = 0
        for entry in raw {
            guard let provider = MenuBarProvider(rawValue: entry) else { continue }

            // At most `menuBarSlotCount - 1` hidden slots; the menu bar must always
            // show something. `none` is checked by count, not by duplicate, so a
            // stored preference may legitimately hide more than one slot.
            if provider == .none {
                guard hiddenCount < menuBarSlotCount - 1 else { continue }
                hiddenCount += 1
            } else if slots.contains(provider) {
                continue
            }

            slots.append(provider)

            if slots.count == menuBarSlotCount { break }
        }

        // Backfill from real providers so the popover always has a field per slot.
        for provider in MenuBarProvider.realProviders where slots.count < menuBarSlotCount {
            if !slots.contains(provider) {
                slots.append(provider)
            }
        }

        return slots.isEmpty ? fallback : Array(slots.prefix(menuBarSlotCount))
    }

    /// `None` is only selectable while at least one other slot still shows a
    /// provider: the menu bar must never end up empty.
    func canHideSlot(at index: Int) -> Bool {
        guard index >= 0, index < Self.menuBarSlotCount else { return false }
        return menuBarSlots.enumerated().contains { offset, provider in
            offset != index && provider != .none
        }
    }

    func setMenuBarSlot(_ provider: MenuBarProvider, at index: Int) {
        guard index >= 0, index < Self.menuBarSlotCount else { return }

        var slots = menuBarSlots
        while slots.count < Self.menuBarSlotCount {
            let filler = MenuBarProvider.realProviders.first { !slots.contains($0) } ?? .chatGPT
            slots.append(filler)
        }

        guard slots[index] != provider else { return }

        if provider == .none {
            // Every other slot must keep a provider, or the menu-bar item vanishes.
            let otherIsVisible = slots.enumerated().contains { offset, existing in
                offset != index && existing != .none
            }
            guard otherIsVisible else { return }
            slots[index] = .none
        } else if let existing = slots.firstIndex(of: provider) {
            // Swapping keeps slots distinct instead of blanking the other one.
            slots.swapAt(index, existing)
        } else {
            slots[index] = provider
        }

        menuBarSlots = Array(slots.prefix(Self.menuBarSlotCount))
        UserDefaults.standard.set(menuBarSlots.map(\.rawValue), forKey: Self.menuBarSlotsKey)
        onChange?()
    }

    func setCursorStatusMetric(_ metric: CursorStatusMetric) {
        guard metric != cursorStatusMetric else { return }
        cursorStatusMetric = metric
        UserDefaults.standard.set(metric.rawValue, forKey: Self.cursorStatusMetricKey)
        onChange?()
    }

    func setChatGPTStatusMetric(_ metric: ChatGPTSessionWindow) {
        chatGPTStatusMetric = metric
        UserDefaults.standard.set(metric.rawValue, forKey: Self.chatGPTStatusMetricKey)
        onChange?()
    }

    func setOpenCodeStatusMetric(_ metric: UsageWindowMetric) {
        openCodeStatusMetric = metric
        UserDefaults.standard.set(metric.rawValue, forKey: Self.openCodeStatusMetricKey)
        onChange?()
    }

    func setCommandCodeStatusMetric(_ metric: UsageWindowMetric) {
        commandCodeStatusMetric = metric
        UserDefaults.standard.set(metric.rawValue, forKey: Self.commandCodeStatusMetricKey)
        onChange?()
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
            return
        }

        guard pendingRequests == 0 else { return }
        pendingRequests = 6

        if chatGPTUsage == nil {
            chatGPTStatus = .loading
        }
        if cursorUsage == nil {
            cursorStatus = .loading
        }
        if hermesUsage == nil {
            hermesStatus = .loading
        }
        if deepSeekUsage == nil {
            deepSeekStatus = .loading
        }
        if openCodeUsage == nil {
            openCodeStatus = .loading
        }
        if commandCodeUsage == nil {
            commandCodeStatus = .loading
        }
        onChange?()

        ChatGPTUsageClient.fetch { [weak self] result in
            DispatchQueue.main.async {
                self?.applyChatGPT(result)
            }
        }

        CursorUsageClient.fetch { [weak self] result in
            DispatchQueue.main.async {
                self?.applyCursor(result)
            }
        }

        HermesUsageClient.fetch { [weak self] result in
            DispatchQueue.main.async {
                self?.applyHermes(result)
            }
        }

        DeepSeekUsageClient.fetch { [weak self] result in
            DispatchQueue.main.async {
                self?.applyDeepSeek(result)
            }
        }

        OpenCodeUsageClient.fetch { [weak self] result in
            DispatchQueue.main.async {
                self?.applyOpenCode(result)
            }
        }

        CommandCodeUsageClient.fetch { [weak self] result in
            DispatchQueue.main.async {
                self?.applyCommandCode(result)
            }
        }
    }

    var compactStatus: String {
        visibleMenuBarProviders
            .filter { $0 != .none }
            .map { "\($0.label) \(value(for: $0) ?? "--")" }
            .joined(separator: "  ")
    }

    /// Menu-bar display value for a provider: percent for quota-based ones,
    /// dollar balance for DeepSeek (which has no percent concept).
    func value(for provider: MenuBarProvider) -> String? {
        switch provider {
        case .chatGPT:
            return chatGPTStatusMetric.percent(
                from: chatGPTUsage,
                preference: chatGPTStatusMetric
            ).map { formatPercent($0) }
        case .cursor:
            return cursorStatusMetric.percent(from: cursorUsage).map { formatPercent($0) }
        case .hermes:
            return hermesUsage?.usedPercent.map { formatPercent($0) }
        case .deepSeek:
            return deepSeekUsage.map { formatBalance($0.totalBalance, currency: $0.currency) }
        case .openCode:
            return openCodeStatusMetric.percent(
                from: openCodeUsage,
                preference: openCodeStatusMetric
            ).map { formatPercent($0) }
        case .commandCode:
            return commandCodeStatusMetric.percent(
                from: commandCodeUsage,
                preference: commandCodeStatusMetric
            ).map { formatPercent($0) }
        case .none:
            return nil
        }
    }

    var statusSeverity: StatusSeverity {
        let chatGPTPercent = chatGPTStatusMetric.percent(
            from: chatGPTUsage,
            preference: chatGPTStatusMetric
        ) ?? 0
        let cursorPercent = cursorStatusMetric.percent(from: cursorUsage) ?? 0
        let hermesPercent = hermesUsage?.usedPercent ?? 0
        let openCodePercent = openCodeStatusMetric.percent(
            from: openCodeUsage,
            preference: openCodeStatusMetric
        ) ?? 0
        let commandCodePercent = commandCodeStatusMetric.percent(
            from: commandCodeUsage,
            preference: commandCodeStatusMetric
        ) ?? 0
        let highest = max(
            chatGPTPercent,
            max(cursorPercent, max(hermesPercent, max(openCodePercent, commandCodePercent)))
        )

        if highest >= 90 {
            return .critical
        }
        if highest >= 75 {
            return .warning
        }
        return .normal
    }

    private func applyChatGPT(_ result: Result<ChatGPTUsage, UsageClientError>) {
        switch result {
        case .success(let usage):
            chatGPTUsage = usage
            chatGPTStatus = .ready
            lastUpdated = Date()
        case .failure(let error):
            chatGPTStatus = chatGPTUsage == nil ? .unavailable(error.message) : .stale(error.message)
        }

        finishRequest()
    }

    private func applyCursor(_ result: Result<CursorUsage, UsageClientError>) {
        switch result {
        case .success(let usage):
            cursorUsage = usage
            cursorStatus = .ready
            lastUpdated = Date()
        case .failure(let error):
            cursorStatus = cursorUsage == nil ? .unavailable(error.message) : .stale(error.message)
        }

        finishRequest()
    }

    private func applyHermes(_ result: Result<HermesUsage, UsageClientError>) {
        switch result {
        case .success(let usage):
            hermesUsage = usage
            hermesStatus = .ready
            lastUpdated = Date()
        case .failure(let error):
            hermesStatus = hermesUsage == nil ? .unavailable(error.message) : .stale(error.message)
        }

        finishRequest()
    }

    private func applyDeepSeek(_ result: Result<DeepSeekUsage, UsageClientError>) {
        switch result {
        case .success(let usage):
            deepSeekUsage = usage
            deepSeekStatus = .ready
            lastUpdated = Date()
        case .failure(let error):
            deepSeekStatus = deepSeekUsage == nil ? .unavailable(error.message) : .stale(error.message)
        }

        finishRequest()
    }

    private func applyOpenCode(_ result: Result<OpenCodeUsage, UsageClientError>) {
        switch result {
        case .success(let usage):
            openCodeUsage = usage
            openCodeStatus = .ready
            lastUpdated = Date()
        case .failure(let error):
            openCodeStatus = openCodeUsage == nil ? .unavailable(error.message) : .stale(error.message)
        }

        finishRequest()
    }

    private func applyCommandCode(_ result: Result<CommandCodeUsage, UsageClientError>) {
        switch result {
        case .success(let usage):
            commandCodeUsage = usage
            commandCodeStatus = .ready
            lastUpdated = Date()
        case .failure(let error):
            commandCodeStatus = commandCodeUsage == nil ? .unavailable(error.message) : .stale(error.message)
        }

        finishRequest()
    }

    private func finishRequest() {
        pendingRequests = max(pendingRequests - 1, 0)
        onChange?()
    }
}

enum StatusSeverity {
    case normal
    case warning
    case critical
}

/// Keeps the configured slot layout intact while hiding providers whose local
/// credentials disappeared. If that would blank the entire menu bar, the first
/// available provider temporarily occupies one slot instead.
enum VisibleMenuBarProviders {
    static func resolve(
        slots: [MenuBarProvider],
        availability: ProviderAvailability
    ) -> [MenuBarProvider] {
        let visible = slots.filter { $0 == .none || availability[$0] }
        guard !visible.contains(where: { $0 != .none }) else { return visible }

        guard let fallback = MenuBarProvider.realProviders.first(where: { availability[$0] }) else {
            return visible
        }
        return [fallback]
    }
}

/// Providers selectable for the three menu-bar slots. `.none` blanks a slot.
enum MenuBarProvider: String, CaseIterable, Identifiable {
    case chatGPT
    case cursor
    case hermes
    case deepSeek
    case openCode
    case commandCode

    /// A deliberately empty slot: shows nothing in the menu bar.
    case none

    var id: String { rawValue }

    /// Providers that actually supply a value. `.none` is excluded so backfill and
    /// filler logic never picks a blank slot.
    static var realProviders: [MenuBarProvider] {
        allCases.filter { $0 != .none }
    }

    var title: String {
        switch self {
        case .chatGPT: return "ChatGPT"
        case .cursor: return "Cursor"
        case .hermes: return "Nous"
        case .deepSeek: return "DeepSeek"
        case .openCode: return "OpenCode"
        case .commandCode: return "CmdCode"
        case .none: return "None"
        }
    }

    var slotTitle: String {
        switch self {
        case .chatGPT: return "ChatGPT — selected window"
        case .cursor: return "Cursor — selected bucket"
        case .hermes: return "Nous — subscription credits"
        case .deepSeek: return "DeepSeek — balance"
        case .openCode: return "OpenCode — selected window"
        case .commandCode: return "CommandCode — selected window"
        case .none: return "None — hidden"
        }
    }

    var label: String {
        switch self {
        case .chatGPT: return "G"
        case .cursor: return "C"
        case .hermes: return "N"
        case .deepSeek: return "D"
        case .openCode: return "O"
        case .commandCode: return "CC"
        case .none: return ""
        }
    }
}
