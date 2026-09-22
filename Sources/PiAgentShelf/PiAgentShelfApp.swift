import AppKit
import Carbon
import SwiftUI

@main
enum PiAgentShelfApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let alwaysOnTopDefaultsKey = "alwaysOnTop"

    private var store: AgentStore!
    private var window: NSWindow!
    private let menuBarPopover = NSPopover()
    private var statusItem: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private var isAlwaysOnTop: Bool {
        get { UserDefaults.standard.bool(forKey: Self.alwaysOnTopDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.alwaysOnTopDefaultsKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()

        let target = GhosttyClient.runningTarget()
        store = AgentStore(target: target)
        configureWindow()
        configureMenuBarPopover()
        configureStatusItem()
        registerGlobalHotKey()
        store.start()
        DispatchQueue.main.async { [weak self] in
            self?.showMenuBarWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DispatchQueue.main.async { [weak self] in
            self?.showMenuBarWindow()
        }
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        store.refresh()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu(title: "Main Menu")
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Pi Agent Shelf")

        appMenu.addItem(
            withTitle: "About Pi Agent Shelf",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Pi Agent Shelf",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let alwaysOnTopItem = NSMenuItem(
            title: "Always on Top",
            action: #selector(toggleAlwaysOnTop(_:)),
            keyEquivalent: ""
        )
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = isAlwaysOnTop ? .on : .off
        windowMenu.addItem(alwaysOnTopItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func configureWindow() {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 800)
        let width = min(640, visibleFrame.width - 80)
        let height = min(680, visibleFrame.height - 100)
        let rootView = ShelfView(store: store) { [weak self] agent in
            self?.store.focus(agent) { _ in }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pi Agent Shelf"
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.level = isAlwaysOnTop ? .floating : .normal
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        self.window = window
    }

    private func configureMenuBarPopover() {
        var rootView = ShelfView(store: store) { [weak self] agent in
            guard let self else { return }
            store.focus(agent) { [weak self] success in
                if success {
                    self?.menuBarPopover.performClose(nil)
                }
            }
        }

        rootView.onDismiss = { [weak self] in
            self?.menuBarPopover.performClose(nil)
        }

        menuBarPopover.behavior = .transient
        menuBarPopover.animates = true
        menuBarPopover.contentSize = NSSize(width: 560, height: 600)
        menuBarPopover.contentViewController = NSHostingController(rootView: rootView)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "PiAgentShelf.StatusItem"

        if let button = item.button {
            let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let image = NSImage(
                systemSymbolName: "rectangle.stack",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(configuration)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(toggleMenuBarWindow(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Open Pi Agent Shelf menu — Control–Option–P"
            button.setAccessibilityIdentifier("PiAgentShelf.StatusItem")
            button.setAccessibilityTitle("Open Pi Agent Shelf menu")
        }

        statusItem = item
    }

    private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.refresh()
    }

    @objc private func toggleMenuBarWindow(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            menuBarPopover.performClose(nil)
            let menu = NSMenu()
            let quitItem = menu.addItem(
                withTitle: "Quit Pi Agent Shelf",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
            quitItem.target = NSApp
            NSMenu.popUpContextMenu(menu, with: event, for: sender)
            return
        }

        if menuBarPopover.isShown {
            menuBarPopover.performClose(sender)
        } else {
            showMenuBarWindow()
        }
    }

    private func showMenuBarWindow() {
        guard let button = statusItem?.button else { return }

        if !menuBarPopover.isShown {
            configureMenuBarPopover()
        }
        let visibleFrame = button.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 800, height: 800)
        menuBarPopover.contentSize = NSSize(
            width: min(560, visibleFrame.width - 40),
            height: min(600, visibleFrame.height - 40)
        )
        menuBarPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        store.refresh()
    }

    @objc private func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        isAlwaysOnTop.toggle()
        window.level = isAlwaysOnTop ? .floating : .normal
        sender.state = isAlwaysOnTop ? .on : .off
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
                    appDelegate.showMenuBarWindow()
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
