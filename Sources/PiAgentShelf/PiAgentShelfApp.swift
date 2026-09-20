import AppKit
import Carbon
import SwiftUI

@main
struct PiAgentShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AgentStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        registerGlobalHotKey()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.stack",
                accessibilityDescription: "Pi agents"
            )
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Pi Agent Shelf — Control-Option-P"
        }
        statusItem = item
    }

    private func configurePopover() {
        let rootView = ShelfView(store: store) { [weak self] agent in
            guard let self else { return }
            self.store.focus(agent) { success in
                if success {
                    self.popover.performClose(nil)
                }
            }
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: rootView)
        updatePopoverSize()
    }

    private func updatePopoverSize() {
        let availableWidth = NSScreen.main?.visibleFrame.width ?? 1040
        popover.contentSize = NSSize(width: min(1040, availableWidth - 40), height: 174)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        guard let button = statusItem?.button else { return }
        store.refresh()
        updatePopoverSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    appDelegate.togglePopover(nil)
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: 0x50494153, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }
}
