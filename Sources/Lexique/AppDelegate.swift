import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: PanelController!
    private var hotKey: GlobalHotKey!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        panelController = PanelController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.statusIcon()
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        hotKey = GlobalHotKey { [weak self] in self?.panelController.toggle() }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.panelController.show()
            if let word = ProcessInfo.processInfo.environment["LEXIQUE_WORD"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.panelController.open(word: word)
                }
            }
        }
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Lexique", action: nil, keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Lexique", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Lexique", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private static func statusIcon() -> NSImage {
        let text = NSAttributedString(string: "Lex", attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.black,
            .kern: -0.2
        ])
        let textSize = text.size()
        let image = NSImage(size: NSSize(width: ceil(textSize.width), height: 18), flipped: false) { rect in
            text.draw(at: NSPoint(x: 0, y: (rect.height - textSize.height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            panelController.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Lexique", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show History Folder in Finder", action: #selector(revealHistoryFolder), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show Dictionary Folder in Finder", action: #selector(revealFolder), keyEquivalent: "").target = self

        let cacheMenu = NSMenu()
        for (index, profile) in Catalog.shared.profiles.enumerated() {
            let item = NSMenuItem(title: "Release \(profile.name) Cache", action: #selector(releaseCache(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            cacheMenu.addItem(item)
        }
        if !cacheMenu.items.isEmpty {
            let cacheItem = NSMenuItem(title: "Release Cache", action: nil, keyEquivalent: "")
            cacheItem.submenu = cacheMenu
            menu.addItem(cacheItem)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self

        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func openPanel() { panelController.show() }

    @objc private func revealFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: Catalog.shared.directory))
    }

    @objc private func revealHistoryFolder() {
        HistoryStore.shared.revealInFinder()
    }

    @objc private func openHistory(_ sender: NSMenuItem) {
        panelController.openHistory(profileIndex: sender.tag)
    }

    @objc private func releaseCache(_ sender: NSMenuItem) {
        Catalog.shared.releaseCache(profileIndex: sender.tag)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
