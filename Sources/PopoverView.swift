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

    var body: some View {
        VStack(alignment: .leading, spacing: CatelToken.sectionGap) {
            menuBarPicker
            chatGPTSection
            cursorSection
            nousSection
            deepSeekSection
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
                        isNoneAvailable: monitor.canHideSlot(at: index),
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
            status: monitor.chatGPTStatus
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

                    if let reset = formatReset(usage.billingCycleEnd) {
                        MicroText("Cycle resets in \(reset)")
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

    /// Matches the Paper caption shape: "$20.44 of $22.00 left  ·  resets in 29d 6h".
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
            parts.append("resets in \(reset)")
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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(CatelToken.divider)
                .frame(height: 1)

            HStack {
                MicroText(lastUpdatedText)

                Spacer(minLength: 0)

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

/// Section shell: title + tag row, optional stale note under the content.
private struct ProviderSection<Content: View>: View {
    let title: String
    let tag: String
    let status: ProviderStatus
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: CatelToken.titleFontSize, weight: .semibold))
                    .foregroundStyle(CatelToken.textPrimary)

                Text(tag)
                    .font(.system(size: CatelToken.tagFontSize, weight: .medium))
                    .foregroundStyle(CatelToken.textSecondary)
            }

            content

            if case .stale(let message) = status {
                StaleNote(message: message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let isNoneAvailable: Bool
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
        .accessibilityLabel("Menu bar slot: \(provider.title)")
    }

    private func presentMenu() {
        let menu = NSMenu()

        for option in MenuBarProvider.allCases {
            let item = NSMenuItem(
                title: option.title,
                action: #selector(MenuBarSlotTarget.select(_:)),
                keyEquivalent: ""
            )
            item.representedObject = option.rawValue
            item.state = option == provider ? .on : .off
            // Grey out `None` when the other slot is already hidden.
            if option == .none, !isNoneAvailable {
                item.isEnabled = false
            }
            item.target = MenuBarSlotTarget.shared
            menu.addItem(item)
        }

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

/// Two-column meter without a radio, used by ChatGPT windows.
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

                Spacer(minLength: 0)

                ValueText(
                    window.map { formatPercent($0.usedPercent) } ?? "--",
                    color: color
                )
            }

            UsageBar(value: window?.usedPercent ?? 0, color: color)

            MicroText(formatReset(window?.resetAt).map { "resets in \($0)" } ?? "resets unavailable")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Content width plus the 12pt padding on each side.
    static let popoverSize = NSSize(width: 300, height: 452)

    init(monitor: UsageMonitor, pointerChanged: @escaping (Bool) -> Void) {
        self.monitor = monitor
        self.pointerChanged = pointerChanged
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

        let hostingView = NSHostingView(rootView: PopoverView(monitor: monitor))
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
