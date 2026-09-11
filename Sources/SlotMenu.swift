import AppKit

/// A disabled menu row that tells the pointer it cannot be chosen.
///
/// AppKit greys a disabled item out but keeps the plain arrow cursor, so an
/// unavailable choice looks like any other until it is clicked and nothing
/// happens. This view keeps the native disabled look (it draws the row through
/// AppKit's own menu-item cell, so font, inset and alignment match the other
/// rows), shows the "operation not allowed" cursor while the pointer is over it,
/// and swallows the click as a second line of defence.
final class UnavailableMenuRowView: NSView {
    private let menuItem: NSMenuItem
    private var trackingArea: NSTrackingArea?

    init(menuItem: NSMenuItem) {
        self.menuItem = menuItem
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Cursor rect: the documented way to change the pointer over a region.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .operationNotAllowed)
    }

    // `.activeAlways` so tracking still works inside a menu window, which is not
    // always the key window.
    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        super.updateTrackingAreas()

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.operationNotAllowed.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    /// Never forward the click, so no action can fire from this row.
    override func mouseDown(with event: NSEvent) {}

    override func draw(_ dirtyRect: NSRect) {
        let cell = NSMenuItemCell(textCell: menuItem.title)
        cell.menuItem = menuItem
        cell.needsSizing = true
        cell.calcSize()
        cell.drawTitle(withFrame: bounds, in: self)
    }
}

/// Builds the "pick a provider for this slot" menu.
///
/// One builder for both the popover picker and the status-item right-click menu,
/// so the availability rule can never drift between them.
enum SlotMenuFactory {
    static func makeMenu(
        selected: MenuBarProvider,
        canHideNone: Bool,
        slotIndex: Int,
        target: AnyObject,
        action: Selector
    ) -> NSMenu {
        let menu = NSMenu()
        // Manual enabling. With AppKit's automatic validation, an item whose target
        // responds to the action is re-enabled before display, which would make the
        // unavailable `None` row look and behave as if it were selectable.
        menu.autoenablesItems = false

        var noneItem: NSMenuItem?

        for provider in MenuBarProvider.allCases {
            let item = NSMenuItem(title: provider.title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = provider.rawValue
            item.tag = slotIndex
            item.state = provider == selected ? .on : .off

            if provider == .none {
                item.isEnabled = canHideNone
                noneItem = item
            }

            menu.addItem(item)
        }

        if let noneItem, !noneItem.isEnabled {
            attachUnavailableRow(to: noneItem, in: menu)
        }

        return menu
    }

    /// Swaps the disabled row's content for the cursor-aware view. Runs after every
    /// item exists so `menu.size` already reflects the final native width and rows.
    private static func attachUnavailableRow(to item: NSMenuItem, in menu: NSMenu) {
        let rowHeight = menu.size.height / CGFloat(menu.numberOfItems)
        let view = UnavailableMenuRowView(menuItem: item)
        view.frame = NSRect(x: 0, y: 0, width: menu.size.width, height: rowHeight)
        item.view = view
    }

    /// Pops a slot menu and clears any cursor that row may have left behind, so a
    /// missed exit can never strand the "operation not allowed" pointer.
    static func popUp(_ menu: NSMenu, at point: NSPoint, in view: NSView? = nil) {
        menu.popUp(positioning: nil, at: point, in: view)
        NSCursor.arrow.set()
    }
}
