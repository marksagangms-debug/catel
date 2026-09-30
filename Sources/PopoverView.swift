import AppKit
import SwiftUI

/// Design tokens lifted from the Paper file "Catel" → artboard "Popover — Light Rebuild".
/// Values are the exact computed styles from Paper; keep them in sync when the design changes.
enum CatelToken {
    // Surfaces
    static let fieldSurface = Color(nsColor: .controlBackgroundColor)
    static let fieldBorder = Color(nsColor: .separatorColor)
    static let divider = Color(nsColor: .separatorColor)
    static let track = Color.primary.opacity(0.16)

    // Text: adaptive so the popover stays legible in both appearances.
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)

    // Provider accents: fixed hues that read on light and dark grounds.
    static let chatGPT = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)
    static let cursor = Color(red: 88 / 255, green: 86 / 255, blue: 214 / 255)
    static let nous = Color(red: 255 / 255, green: 149 / 255, blue: 0 / 255)
    static let deepSeek = Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255)
    static let openCode = Color(red: 175 / 255, green: 82 / 255, blue: 222 / 255)
    static let commandCode = Color(red: 191 / 255, green: 90 / 255, blue: 42 / 255)

    // Metrics
    static let contentPadding: CGFloat = 12
    static let sectionGap: CGFloat = 12
    static let fieldHeight: CGFloat = 30
    static let fieldRadius: CGFloat = 7
    static let fieldPadding: CGFloat = 10
    static let fieldFontSize: CGFloat = 12
    static let columnGap: CGFloat = 12
    static let trackHeight: CGFloat = 5
    static let trackRadius: CGFloat = 3
    static let radioSize: CGFloat = 9
    static let radioDot: CGFloat = 4

    // Type scale
    static let titleFontSize: CGFloat = 13
    static let valueFontSize: CGFloat = 12
    static let labelFontSize: CGFloat = 10
    static let tagFontSize: CGFloat = 10
    static let microFontSize: CGFloat = 9
}

struct PopoverView: View {
    @ObservedObject var monitor: UsageMonitor
    /// Opens the Settings window (provider API keys). Injected by the hosting
    /// controller so the popover stays free of window/AppDelegate knowledge.
    var openSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: CatelToken.sectionGap) {
            menuBarPicker

            if monitor.isAvailable(.chatGPT) {
                chatGPTSection
            }
            if monitor.isAvailable(.cursor) {
                cursorSection
            }
            if monitor.isAvailable(.hermes) {
                nousSection
            }
            if monitor.isAvailable(.deepSeek) {
                deepSeekSection
            }
            if monitor.isAvailable(.openCode) {
                openCodeSection
            }
            if monitor.isAvailable(.commandCode) {
                commandCodeSection
            }

            footer
        }
        .padding(CatelToken.contentPadding)
        .frame(width: PopoverViewController.popoverSize.width, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var menuBarPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Menu bar")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(CatelToken.textSecondary)

                Spacer(minLength: 0)

                Text("\(UsageMonitor.menuBarSlotCount) slots")
                    .font(.system(size: 11))
                    .foregroundStyle(CatelToken.textSecondary)
            }

            HStack(spacing: 8) {
                ForEach(Array(monitor.menuBarSlots.enumerated()), id: \.offset) { index, provider in
                    MenuBarSlotPicker(
                        provider: provider,
                        index: index,
                        isNoneAvailable: monitor.canHideSlot(at: index),
                        availableProviders: monitor.availableProviders,
                        onChange: { monitor.setMenuBarSlot($0, at: index) }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var chatGPTSection: some View {
        ProviderSection(
            title: "ChatGPT",
            tag: monitor.chatGPTUsage?.planName?.uppercased() ?? "PLAN",
            status: monitor.chatGPTStatus,
            accessory: {
                ChatGPTSessionSelector(
                    selected: monitor.chatGPTStatusMetric,
                    accent: CatelToken.chatGPT,
                    onSelect: monitor.setChatGPTStatusMetric
                )
            }
        ) {
            if let usage = monitor.chatGPTUsage {
                HStack(alignment: .top, spacing: CatelToken.columnGap) {
                    WindowMeter(
                        title: "5-hour",
                        window: usage.primaryWindow,
                        color: CatelToken.chatGPT
                    )
                    WindowMeter(
                        title: "7-day",
                        window: usage.secondaryWindow,
                        color: CatelToken.chatGPT
                    )
                }
            } else {
                ProviderStateView(status: monitor.chatGPTStatus)
            }
        }
    }

    private var cursorSection: some View {
        ProviderSection(
            title: "Cursor",
            tag: monitor.cursorUsage?.planName?.uppercased() ?? "PRO",
            status: monitor.cursorStatus
        ) {
            if let usage = monitor.cursorUsage {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: CatelToken.columnGap) {
                        PercentMeter(
                            title: "Cursor Models",
                            percent: usage.cursorModelsPercentUsed,
                            color: CatelToken.cursor,
                            isSelected: monitor.cursorStatusMetric == .cursorModels
                        ) {
                            monitor.setCursorStatusMetric(.cursorModels)
                        }

                        PercentMeter(
                            title: "Other Models",
                            percent: usage.otherModelsPercentUsed,
                            color: CatelToken.cursor,
                            isSelected: monitor.cursorStatusMetric == .otherModels
                        ) {
                            monitor.setCursorStatusMetric(.otherModels)
                        }
                    }

                    if let reset = formatCycleCaption(usage.billingCycleEnd) {
                        MicroText(reset)
                    }
                }
            } else {
                ProviderStateView(status: monitor.cursorStatus)
            }
        }
    }

    private var nousSection: some View {
        ProviderSection(
            title: "Nous",
            tag: monitor.hermesUsage?.planName?.uppercased() ?? "PORTAL",
            status: monitor.hermesStatus
        ) {
            if let usage = monitor.hermesUsage {
                SingleMeter(
                    title: "Subscription",
                    percent: usage.usedPercent,
                    color: CatelToken.nous,
                    caption: nousCaption(usage)
                )
            } else {
                ProviderStateView(status: monitor.hermesStatus)
            }
        }
    }

    /// Matches the Paper caption shape: "$20.44 of $22.00 left  ·  29d 6h".
    private func nousCaption(_ usage: HermesUsage) -> String? {
        var parts: [String] = []

        if let remaining = usage.creditsRemaining, let monthly = usage.monthlyCredits {
            parts.append("\(formatDollars(remaining)) of \(formatDollars(monthly)) left")
        } else if let remaining = usage.creditsRemaining {
            parts.append("\(formatDollars(remaining)) left")
        }

        if let purchased = usage.purchasedCreditsRemaining, purchased > 0 {
            parts.append("top-up \(formatDollars(purchased))")
        }

        if let reset = formatReset(usage.billingCycleEnd) {
            parts.append(reset)
        }

        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private var deepSeekSection: some View {
        ProviderSection(
            title: "DeepSeek",
            tag: "API",
            status: monitor.deepSeekStatus
        ) {
            if let usage = monitor.deepSeekUsage {
                MeterRow(
                    title: "Balance",
                    value: formatBalance(usage.totalBalance, currency: usage.currency),
                    color: CatelToken.deepSeek
                )
            } else {
                ProviderStateView(status: monitor.deepSeekStatus)
            }
        }
    }

    private var openCodeSection: some View {
        ProviderSection(
            title: "OpenCode Go",
            tag: "GO",
            status: monitor.openCodeStatus,
            accessory: {
                WindowMetricSelector(
                    selected: monitor.openCodeStatusMetric,
                    accent: CatelToken.openCode,
                    onSelect: monitor.setOpenCodeStatusMetric
                )
            }
        ) {
            if let usage = monitor.openCodeUsage {
                HStack(alignment: .top, spacing: CatelToken.columnGap) {
                    WindowMeter(
                        title: "5-hour",
                        window: usage.rolling,
                        color: CatelToken.openCode
                    )
                    WindowMeter(
                        title: "Weekly",
                        window: usage.weekly,
                        color: CatelToken.openCode
                    )
                    WindowMeter(
                        title: "Monthly",
                        window: usage.monthly,
                        color: CatelToken.openCode
                    )
                }
            } else {
                ProviderStateView(status: monitor.openCodeStatus)
            }
        }
    }

    private var commandCodeSection: some View {
        ProviderSection(
            title: "CommandCode",
            tag: monitor.commandCodeUsage?.planName?.uppercased() ?? "API",
            status: monitor.commandCodeStatus,
            accessory: {
                WindowMetricSelector(
                    selected: monitor.commandCodeStatusMetric,
                    accent: CatelToken.commandCode,
                    onSelect: monitor.setCommandCodeStatusMetric
                )
            }
        ) {
            if let usage = monitor.commandCodeUsage {
                HStack(alignment: .top, spacing: CatelToken.columnGap) {
                    WindowMeter(
                        title: "5-hour",
                        window: usage.fiveHour,
                        color: CatelToken.commandCode
                    )
                    WindowMeter(
                        title: "Weekly",
                        window: usage.weekly,
                        color: CatelToken.commandCode
                    )
                    WindowMeter(
                        title: "Monthly",
                        window: usage.monthly,
                        color: CatelToken.commandCode
                    )
                }
            } else {
                ProviderStateView(status: monitor.commandCodeStatus)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(CatelToken.divider)
                .frame(height: 1)

            HStack {
                MicroText(lastUpdatedText)

                Spacer(minLength: 8)

                Button {
                    monitor.refreshProviderAvailability()
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CatelToken.textSecondary)
                .accessibilityLabel("Refresh configured providers")

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CatelToken.textSecondary)
                .accessibilityLabel("Catel Settings")

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CatelToken.textSecondary)
            }
        }
    }

    private var lastUpdatedText: String {
        guard let lastUpdated = monitor.lastUpdated else {
            return "Updating..."
        }
        return "Updated \(lastUpdated.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - Building blocks

/// Section shell: title + tag row, optional compact window selector, optional stale note.
private struct ProviderSection<Content: View, Accessory: View>: View {
    let title: String
    let tag: String
    let status: ProviderStatus
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(
        title: String,
        tag: String,
        status: ProviderStatus,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.tag = tag
        self.status = status
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: CatelToken.titleFontSize, weight: .semibold))
                    .foregroundStyle(CatelToken.textPrimary)

                Text(tag)
                    .font(.system(size: CatelToken.tagFontSize, weight: .medium))
                    .foregroundStyle(CatelToken.textSecondary)

                Spacer(minLength: 4)

                accessory
            }

            content

            if case .stale(let message) = status {
                StaleNote(message: message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ProviderSection where Accessory == EmptyView {
    init(
        title: String,
        tag: String,
        status: ProviderStatus,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            tag: tag,
            status: status,
            accessory: { EmptyView() },
            content: content
        )
    }
}

private struct ChatGPTSessionSelector: View {
    let selected: ChatGPTSessionWindow
    let accent: Color
    let onSelect: (ChatGPTSessionWindow) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ChatGPTSessionWindow.allCases) { session in
                Button {
                    onSelect(session)
                } label: {
                    Text(session.shortTitle)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(
                            selected == session ? accent : CatelToken.textSecondary
                        )
                        .frame(minWidth: 19)
                        .frame(height: 17)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    selected == session
                                        ? accent.opacity(0.12)
                                        : Color.clear
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(session.title) in the status bar")
                .accessibilityAddTraits(selected == session ? .isSelected : [])
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 21)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(CatelToken.fieldSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(CatelToken.fieldBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status bar window")
    }
}

private struct WindowMetricSelector: View {
    let selected: UsageWindowMetric
    let accent: Color
    let onSelect: (UsageWindowMetric) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(UsageWindowMetric.allCases) { metric in
                Button {
                    onSelect(metric)
                } label: {
                    Text(metric.shortTitle)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(
                            selected == metric ? accent : CatelToken.textSecondary
                        )
                        .frame(minWidth: 19)
                        .frame(height: 17)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    selected == metric
                                        ? accent.opacity(0.12)
                                        : Color.clear
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(metric.title) in the status bar")
                .accessibilityAddTraits(selected == metric ? .isSelected : [])
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 21)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(CatelToken.fieldSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(CatelToken.fieldBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status bar window")
    }
}

private struct MicroText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: CatelToken.microFontSize))
            .foregroundStyle(CatelToken.textSecondary)
    }
}

/// One menu-bar slot. A plain Button draws our label as authored; `Menu` would
/// let AppKit substitute its own chrome (leading chevron, system font, no fill).
private struct MenuBarSlotPicker: View {
    let provider: MenuBarProvider
    /// Slot position, used for the accessibility label and the `None` rule.
    let index: Int
    let isNoneAvailable: Bool
    let availableProviders: [MenuBarProvider]
    let onChange: (MenuBarProvider) -> Void

    var body: some View {
        Button {
            presentMenu()
        } label: {
            HStack(spacing: 0) {
                Text(provider.title)
                    .font(.system(size: CatelToken.fieldFontSize, weight: .medium))
                    .foregroundStyle(CatelToken.textPrimary)
                    .lineLimit(1)
                    // Three fields share one row, so the longest name ("DeepSeek")
                    // scales down instead of truncating.
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 6)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(CatelToken.textSecondary)
            }
            .padding(.horizontal, CatelToken.fieldPadding)
            .frame(maxWidth: .infinity)
            .frame(height: CatelToken.fieldHeight)
            .background(
                RoundedRectangle(cornerRadius: CatelToken.fieldRadius, style: .continuous)
                    .fill(CatelToken.fieldSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CatelToken.fieldRadius, style: .continuous)
                    .strokeBorder(CatelToken.fieldBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menu bar slot \(index + 1): \(provider.title)")
    }

    private func presentMenu() {
        let menu = SlotMenuFactory.makeMenu(
            selected: provider,
            canHideNone: isNoneAvailable,
            availableProviders: availableProviders,
            slotIndex: index,
            target: MenuBarSlotTarget.shared,
            action: #selector(MenuBarSlotTarget.select(_:))
        )

        MenuBarSlotTarget.shared.onSelect = onChange

        // Pop at the pointer, in SCREEN coordinates (`in: nil` means the point is
        // screen-space, matching NSEvent.mouseLocation). Converting a SwiftUI frame
        // into AppKit window coords is easy to get wrong, and the pointer is
        // guaranteed to be on the field that was just clicked anyway.
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// Target for the slot menu's items; NSMenu actions need an Objective-C object.
private final class MenuBarSlotTarget: NSObject {
    static let shared = MenuBarSlotTarget()
    var onSelect: ((MenuBarProvider) -> Void)?

    @objc func select(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let provider = MenuBarProvider(rawValue: raw)
        else { return }
        onSelect?(provider)
    }
}

/// Compact label-on-left, value-on-right row for balance-style (non-percent) providers.
private struct MeterRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: CatelToken.labelFontSize))
                .foregroundStyle(CatelToken.textSecondary)

            Spacer(minLength: 0)

            ValueText(value, color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ValueText: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: CatelToken.valueFontSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
    }
}

/// Single full-width meter, used by Nous.
private struct SingleMeter: View {
    let title: String
    let percent: Double?
    let color: Color
    let caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: CatelToken.labelFontSize))
                    .foregroundStyle(CatelToken.textSecondary)

                Spacer(minLength: 0)

                ValueText(percent.map(formatPercent) ?? "--", color: color)
            }

            UsageBar(value: percent ?? 0, color: color)

            if let caption {
                MicroText(caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Two-column meter with a selectable radio, used by Cursor.
private struct PercentMeter: View {
    let title: String
    let percent: Double?
    let color: Color
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil

    var body: some View {
        Button {
            onSelect?()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 5) {
                    RadioIndicator(isSelected: isSelected, color: color)

                    Text(title)
                        .font(.system(size: CatelToken.labelFontSize))
                        .foregroundStyle(CatelToken.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    ValueText(percent.map(formatPercent) ?? "--", color: color)
                }

                UsageBar(value: percent ?? 0, color: color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSelect == nil)
    }
}

/// Radio sized to the Paper spec: 9px ring, 4px centre dot, colour-matched to the provider.
private struct RadioIndicator: View {
    let isSelected: Bool
    var color: Color = CatelToken.cursor

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? color.opacity(0.4) : CatelToken.textSecondary.opacity(0.4),
                    lineWidth: 1
                )
                .frame(width: CatelToken.radioSize, height: CatelToken.radioSize)

            if isSelected {
                Circle()
                    .fill(color)
                    .frame(width: CatelToken.radioDot, height: CatelToken.radioDot)
            }
        }
        .frame(width: CatelToken.radioSize, height: CatelToken.radioSize)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Window meter used by ChatGPT, OpenCode Go, and CommandCode. Multi-window
/// selection lives only in the compact title selector.
private struct WindowMeter: View {
    let title: String
    let window: UsageWindow?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: CatelToken.labelFontSize))
                    .foregroundStyle(CatelToken.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                ValueText(
                    window.map { formatPercent($0.usedPercent) } ?? "--",
                    color: color
                )
            }

            UsageBar(value: window?.usedPercent ?? 0, color: color)
            MicroText(formatResetCaption(window?.resetAt))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(window.map { formatPercent($0.usedPercent) } ?? "unavailable")")
    }
}

private struct UsageBar: View {
    let value: Double
    let color: Color

    /// Keeps very small values readable; a 7% fill on a 120px track is ~8px
    /// otherwise, which reads as a stray pixel rather than a proportion.
    private static let minimumVisibleFill: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: CatelToken.trackRadius, style: .continuous)
                    .fill(CatelToken.track)

                RoundedRectangle(cornerRadius: CatelToken.trackRadius, style: .continuous)
                    .fill(color)
                    .frame(width: fillWidth(in: proxy.size.width))
            }
        }
        .frame(height: CatelToken.trackHeight)
    }

    private func fillWidth(in trackWidth: CGFloat) -> CGFloat {
        let fraction = min(max(value, 0), 100) / 100
        guard fraction > 0 else { return 0 }
        return max(trackWidth * fraction, Self.minimumFillFor(trackWidth))
    }

    private static func minimumFillFor(_ trackWidth: CGFloat) -> CGFloat {
        min(minimumVisibleFill, trackWidth)
    }
}

private struct ProviderStateView: View {
    let status: ProviderStatus

    var body: some View {
        HStack(spacing: 6) {
            if case .loading = status {
                ProgressView()
                    .controlSize(.small)
            }

            Text(status.message ?? "Updating...")
                .font(.system(size: CatelToken.labelFontSize))
                .foregroundStyle(CatelToken.textSecondary)
        }
    }
}

private struct StaleNote: View {
    let message: String

    var body: some View {
        MicroText("Stale · \(message)")
    }
}

// MARK: - Hosting

final class PopoverTrackingView: NSView {
    var onPointerChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerChange?(false)
    }
}

final class PopoverViewController: NSViewController {
    private let monitor: UsageMonitor
    private let pointerChanged: (Bool) -> Void
    private let openSettings: () -> Void

    /// Width leaves enough room for the three slot fields, three usage columns,
    /// and compact window selectors beside the OpenCode/CommandCode titles.
    /// Height is the measured intrinsic content height (515pt for the six provider
    /// sections) with the same ~60pt headroom the five-section layout used, so
    /// stale/loading notes still fit.
    static let popoverSize = NSSize(width: 360, height: 575)

    init(
        monitor: UsageMonitor,
        pointerChanged: @escaping (Bool) -> Void,
        openSettings: @escaping () -> Void = {}
    ) {
        self.monitor = monitor
        self.pointerChanged = pointerChanged
        self.openSettings = openSettings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = PopoverTrackingView(
            frame: NSRect(origin: .zero, size: Self.popoverSize)
        )
        rootView.onPointerChange = pointerChanged

        let hostingView = NSHostingView(
            rootView: PopoverView(monitor: monitor, openSettings: openSettings)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: rootView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        view = rootView
        preferredContentSize = Self.popoverSize
    }
}
