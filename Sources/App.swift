import AppKit
import SwiftUI

final class HoverStatusButton: NSButton {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var pointerInside = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = .imageOnly
        refusesFirstResponder = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(image: NSImage) {
        self.image = image
        frame.size = NSSize(
            width: ceil(image.size.width) + 8,
            height: NSStatusBar.system.thickness
        )
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let imageWidth = image?.size.width ?? 0
        return NSSize(
            width: ceil(imageWidth) + 8,
            height: NSStatusBar.system.thickness
        )
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        super.updateTrackingAreas()

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setPointerInside(true)
    }

    override func mouseMoved(with event: NSEvent) {
        setPointerInside(true)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerInside(false)
    }

    private func setPointerInside(_ inside: Bool) {
        guard pointerInside != inside else { return }
        pointerInside = inside
        onHoverChanged?(inside)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusButton: HoverStatusButton!
    private var popover: NSPopover!
    private var monitor: UsageMonitor!

    private var statusPointerInside = false
    private var popoverPointerInside = false
    private var isPinned = false
    private var showWorkItem: DispatchWorkItem?
    private var closeWorkItem: DispatchWorkItem?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        monitor = UsageMonitor()
        monitor.onChange = { [weak self] in
            self?.updateStatusItem()
        }

        configureStatusItem()
        configurePopover()
        installOutsideClickMonitors()
        updateStatusItem()
    }

    deinit {
        showWorkItem?.cancel()
        closeWorkItem?.cancel()

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let button = HoverStatusButton(frame: NSRect(
            x: 0,
            y: 0,
            width: 0,
            height: NSStatusBar.system.thickness
        ))
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Catel")
        button.toolTip = "Catel"

        button.onHoverChanged = { [weak self] isInside in
            self?.statusHoverChanged(isInside)
        }
        statusButton = button
        // The system status-item button does not reliably forward hover tracking events.
        statusItem.view = button
    }

    private func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = PopoverViewController(
            monitor: monitor,
            pointerChanged: { [weak self] isInside in
                self?.popoverHoverChanged(isInside)
            }
        )
        popover.contentSize = NSSize(width: 300, height: 452)
        self.popover = popover
    }

    private func installOutsideClickMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] _ in
            self?.closeIfClickOutside()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            self?.closeIfClickOutside()
            return event
        }
    }

    private func updateStatusItem() {
        guard let statusButton else { return }

        // `.none` slots render nothing: dropping them here means no label and no
        // divider for a hidden slot.
        let segments = monitor.menuBarSlots
            .filter { $0 != .none }
            .map { provider in
                "\(provider.label)\(monitor.value(for: provider) ?? "--")"
            }

        statusButton.update(image: makeTitleImage(segments: segments))
        statusButton.toolTip = "Catel"
        statusItem.length = statusButton.frame.width
    }

    private func makeTitleImage(segments: [String]) -> NSImage {
        let title = makeTitle(segments: segments)
        let bounds = title.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let size = NSSize(width: ceil(bounds.width), height: ceil(bounds.height))

        let image = NSImage(size: size, flipped: false) { rect in
            title.draw(
                with: rect,
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    private func makeTitle(segments: [String]) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        // Template images are tinted by the system for light/dark menu bar backgrounds.
        let textColor = NSColor.black

        let title = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                title.append(divider(font: font, color: textColor))
            }
            title.append(spacedSegment(segment, font: font, color: textColor))
        }
        return title
    }

    private func divider(font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: " | ",
            attributes: [
                .font: font,
                .foregroundColor: color.withAlphaComponent(0.4)
            ]
        )
    }

    private func spacedSegment(
        _ text: String,
        font: NSFont,
        color: NSColor
    ) -> NSAttributedString {
        let label = String(text.prefix(1))
        let value = String(text.dropFirst())
        let result = NSMutableAttributedString(
            string: label,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .kern: 4
            ]
        )
        result.append(
            NSAttributedString(
                string: value,
                attributes: [
                    .font: font,
                    .foregroundColor: color
                ]
            )
        )
        return result
    }

    private func statusHoverChanged(_ isInside: Bool) {
        statusPointerInside = isInside

        if isInside {
            cancelClose()
            refreshIfStale()

            guard !popover.isShown, !isPinned else { return }
            scheduleShow()
        } else {
            cancelShow()
            scheduleCloseIfNeeded()
        }
    }

    private func popoverHoverChanged(_ isInside: Bool) {
        popoverPointerInside = isInside

        if isInside {
            cancelClose()
        } else {
            scheduleCloseIfNeeded()
        }
    }

    private func refreshIfStale() {
        guard
            let lastUpdated = monitor.lastUpdated,
            Date().timeIntervalSince(lastUpdated) < 60
        else {
            monitor.refresh()
            return
        }
    }

    private func scheduleShow() {
        showWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.statusPointerInside, !self.popover.isShown else { return }
            self.showPopover()
        }
        showWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func scheduleCloseIfNeeded() {
        closeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.statusPointerInside, !self.popoverPointerInside, !self.isPinned else {
                return
            }
            self.closePopover()
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func cancelShow() {
        showWorkItem?.cancel()
        showWorkItem = nil
    }

    private func cancelClose() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
    }

    private func showPopover() {
        guard let statusButton, !popover.isShown else { return }

        cancelClose()
        popover.show(
            relativeTo: statusButton.bounds,
            of: statusButton,
            preferredEdge: .minY
        )
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
        isPinned = false
        popoverPointerInside = false
    }

    private func showCursorMetricMenu() {
        guard let statusButton else { return }

        let menu = NSMenu()
        for metric in CursorStatusMetric.allCases {
            let item = NSMenuItem(
                title: metric.title,
                action: #selector(selectCursorMetric(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = metric.rawValue
            item.state = monitor.cursorStatusMetric == metric ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Quick slot switching: assigns one slot, swapping when the provider is
        // already slotted elsewhere so the slots stay distinct. Submenus keep the
        // right-click menu short now that there are three slots.
        for index in 0..<UsageMonitor.menuBarSlotCount {
            let slotItem = NSMenuItem(
                title: "Menu bar slot \(index + 1)",
                action: nil,
                keyEquivalent: ""
            )
            slotItem.submenu = makeSlotMenu(for: index)
            menu.addItem(slotItem)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: statusButton.bounds.height + 4),
            in: statusButton
        )
    }

    /// Provider options for one menu-bar slot. `None` stays visible but greyed out
    /// (and shows the not-allowed cursor) while the other slots already hide
    /// everything: the rule lives in `SlotMenuFactory`, shared with the popover.
    private func makeSlotMenu(for index: Int) -> NSMenu {
        let current = monitor.menuBarSlots.indices.contains(index) ? monitor.menuBarSlots[index] : nil

        return SlotMenuFactory.makeMenu(
            selected: current ?? .none,
            canHideNone: monitor.canHideSlot(at: index),
            slotIndex: index,
            target: self,
            action: #selector(selectSlotProvider(_:))
        )
    }

    @objc private func selectCursorMetric(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let metric = CursorStatusMetric(rawValue: raw)
        else { return }
        monitor.setCursorStatusMetric(metric)
    }

    @objc private func selectSlotProvider(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let provider = MenuBarProvider(rawValue: raw)
        else { return }
        monitor.setMenuBarSlot(provider, at: sender.tag)
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func closeIfClickOutside() {
        guard popover.isShown, let statusButton else { return }

        let mouseLocation = NSEvent.mouseLocation
        let inPopover = popover.contentViewController?.view.window?.frame.contains(mouseLocation) ?? false
        let inStatusItem = statusButton.window?.frame.contains(mouseLocation) ?? false

        if !inPopover && !inStatusItem {
            closePopover()
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showCursorMetricMenu()
            return
        }

        cancelShow()
        cancelClose()

        if popover.isShown {
            if isPinned {
                closePopover()
            } else {
                isPinned = true
            }
        } else {
            isPinned = true
            showPopover()
        }
    }
}

@main
struct CatelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
