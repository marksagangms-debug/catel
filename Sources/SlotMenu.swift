import AppKit

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
        // responds to the action is re-enabled before display, which made the
        // unavailable `None` row look and behave as if it were selectable.
        menu.autoenablesItems = false

        for provider in MenuBarProvider.allCases {
            let item = NSMenuItem(title: provider.title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = provider.rawValue
            item.tag = slotIndex
            item.state = provider == selected ? .on : .off

            // AppKit greys a disabled item out and refuses the click.
            if provider == .none {
                item.isEnabled = canHideNone
            }

            menu.addItem(item)
        }

        return menu
    }
}
