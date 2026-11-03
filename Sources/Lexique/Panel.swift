import AppKit
import WebKit
import AVFoundation

final class AlwaysActionSegmentedControl: NSSegmentedControl {
    override func mouseDown(with event: NSEvent) {
        let before = selectedSegment
        super.mouseDown(with: event)
        if selectedSegment == before, let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
}

final class LexiqueRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        path.fill()
    }
}

final class LexiquePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelController: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, WKNavigationDelegate {
    private let panel: LexiquePanel
    private let searchField = NSTextField()
    private let searchBox = NSView()
    private let searchIcon = NSImageView()
    private let profileBar = NSView()
    private let profileStack = NSStackView()
    private var profileButtons: [NSButton] = []
    private var selectedProfile = 0
    private let statusLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let webView: WKWebView
    private let backButton = NSButton()
    private let headerView = NSView()
    private let ukRow = NSStackView()
    private let usRow = NSStackView()
    private let ukIPA = NSTextField(labelWithString: "")
    private let usIPA = NSTextField(labelWithString: "")
    private lazy var synthesizer = AVSpeechSynthesizer()

    private var results: [(word: String, dict: String)] = []
    private var searchGeneration: UInt64 = 0
    private var showingDetail = false
    private var currentWord = ""

    private let panelSize = NSSize(width: 560, height: 520)

    private var historyKey: String {
        "LexiqueHistory." + (Catalog.shared.currentProfile?.name ?? "default")
    }

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)

        panel = LexiquePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        webView.navigationDelegate = self
        buildUI()
        rebuildProfileControl()
        if !panel.setFrameUsingName("LexiquePanel") { positionTopRight() }
        panel.setFrameAutosaveName("LexiquePanel")

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.keyCode == 53 else { return event }
            self.handleEscape()
            return nil
        }

        Catalog.shared.onChange = { [weak self] in self?.refreshAfterLoad() }
        Catalog.shared.start()
        showHistory()
    }

    // MARK: - UI

    private func buildUI() {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.minSize = NSSize(width: 280, height: 200)

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        profileBar.translatesAutoresizingMaskIntoConstraints = false
        profileBar.wantsLayer = true
        profileBar.layer?.cornerRadius = 6
        profileBar.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        effect.addSubview(profileBar)

        profileStack.translatesAutoresizingMaskIntoConstraints = false
        profileStack.orientation = .horizontal
        profileStack.spacing = 2
        profileBar.addSubview(profileStack)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .right
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        effect.addSubview(statusLabel)

        searchBox.translatesAutoresizingMaskIntoConstraints = false
        searchBox.wantsLayer = true
        searchBox.layer?.cornerRadius = 8
        searchBox.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.35).cgColor
        effect.addSubview(searchBox)

        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        searchBox.addSubview(searchIcon)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Let’s lex…"
        searchField.font = .systemFont(ofSize: 15, weight: .regular)
        searchField.delegate = self
        searchField.focusRingType = .none
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.cell?.usesSingleLineMode = true
        searchBox.addSubview(searchField)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.bezelStyle = .inline
        backButton.isBordered = false
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.isHidden = true
        effect.addSubview(backButton)

        buildHeader()
        effect.addSubview(headerView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("word"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 38
        tableView.style = .plain
        tableView.intercellSpacing = .zero
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.target = self
        tableView.doubleAction = #selector(openSelection)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        effect.addSubview(scrollView)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isHidden = true
        webView.setValue(false, forKey: "drawsBackground")
        effect.addSubview(webView)

        NSLayoutConstraint.activate([
            profileBar.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
            profileBar.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            profileBar.heightAnchor.constraint(equalToConstant: 24),
            profileStack.topAnchor.constraint(equalTo: profileBar.topAnchor, constant: 2),
            profileStack.leadingAnchor.constraint(equalTo: profileBar.leadingAnchor, constant: 2),
            profileStack.bottomAnchor.constraint(equalTo: profileBar.bottomAnchor, constant: -2),
            profileStack.trailingAnchor.constraint(equalTo: profileBar.trailingAnchor, constant: -2),

            statusLabel.centerYAnchor.constraint(equalTo: profileBar.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: profileBar.trailingAnchor, constant: 8),

            searchBox.topAnchor.constraint(equalTo: profileBar.bottomAnchor, constant: 10),
            searchBox.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            searchBox.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            searchBox.heightAnchor.constraint(equalToConstant: 38),

            searchIcon.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 12),
            searchIcon.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 15),
            searchIcon.heightAnchor.constraint(equalToConstant: 15),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: searchBox.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),

            backButton.topAnchor.constraint(equalTo: effect.topAnchor, constant: 10),
            backButton.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
            backButton.widthAnchor.constraint(equalToConstant: 28),
            backButton.heightAnchor.constraint(equalToConstant: 24),

            headerView.topAnchor.constraint(equalTo: effect.topAnchor, constant: 40),
            headerView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            headerView.heightAnchor.constraint(equalToConstant: 48),

            webView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 0),
            webView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
    }

    private func buildHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.isHidden = true

        for (row, tag, ipa, language) in [(ukRow, "英", ukIPA, "en-GB"), (usRow, "美", usIPA, "en-US")] {
            row.orientation = .horizontal
            row.spacing = 6
            row.translatesAutoresizingMaskIntoConstraints = false

            let tagLabel = NSTextField(labelWithString: tag)
            tagLabel.font = .systemFont(ofSize: 12, weight: .medium)
            tagLabel.textColor = .secondaryLabelColor

            ipa.font = .systemFont(ofSize: 14)
            ipa.textColor = .labelColor
            ipa.lineBreakMode = .byTruncatingTail

            let speaker = NSButton()
            speaker.bezelStyle = .inline
            speaker.isBordered = false
            speaker.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Speak")
            speaker.contentTintColor = .secondaryLabelColor
            speaker.identifier = NSUserInterfaceItemIdentifier(language)
            speaker.target = self
            speaker.action = #selector(speakCurrent)
            speaker.translatesAutoresizingMaskIntoConstraints = false
            speaker.widthAnchor.constraint(equalToConstant: 24).isActive = true

            row.addArrangedSubview(tagLabel)
            row.addArrangedSubview(ipa)
            row.addArrangedSubview(speaker)
            headerView.addSubview(row)
        }

        NSLayoutConstraint.activate([
            ukRow.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 2),
            ukRow.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            ukRow.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor),
            usRow.topAnchor.constraint(equalTo: ukRow.bottomAnchor, constant: 8),
            usRow.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            usRow.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor),
        ])
    }

    private func rebuildProfileControl() {
        guard profileButtons.count != Catalog.shared.profiles.count else {
            updateProfileSelection()
            return
        }
        profileButtons.forEach { $0.removeFromSuperview() }
        profileButtons.removeAll()

        for (index, profile) in Catalog.shared.profiles.enumerated() {
            let button = NSButton(title: profile.name, target: self, action: #selector(profileButtonTapped(_:)))
            button.tag = index
            button.isBordered = false
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.wantsLayer = true
            button.layer?.cornerRadius = 4.5
            button.contentTintColor = .secondaryLabelColor
            let width = (profile.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width + 20
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: ceil(width)).isActive = true
            button.heightAnchor.constraint(equalToConstant: 20).isActive = true
            profileStack.addArrangedSubview(button)
            profileButtons.append(button)
        }
        updateProfileSelection()
    }

    private func updateProfileSelection() {
        selectedProfile = Catalog.shared.currentIndex
        for (index, button) in profileButtons.enumerated() {
            let isSelected = index == selectedProfile
            button.layer?.backgroundColor = isSelected
                ? NSColor.textBackgroundColor.withAlphaComponent(0.75).cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = isSelected ? .labelColor : .secondaryLabelColor
        }
    }

    @objc private func profileButtonTapped(_ sender: NSButton) {
        let index = sender.tag
        guard Catalog.shared.profiles.indices.contains(index) else { return }
        selectedProfile = index
        Catalog.shared.switchProfile(index)
        updateProfileSelection()
        searchField.stringValue = ""
        showHistory()
    }

    private func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.maxX - panelSize.width - 12
        let y = frame.maxY - panelSize.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Show / hide

    private var previousApp: NSRunningApplication?

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        showList()
        panel.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    func hide() {
        if showingDetail { webView.loadHTMLString("", baseURL: nil) }
        panel.orderOut(nil)
        previousApp?.activate()
    }

    private func showList() {
        showingDetail = false
        webView.isHidden = true
        scrollView.isHidden = false
        searchBox.isHidden = false
        profileBar.isHidden = false
        statusLabel.isHidden = false
        backButton.isHidden = true
        headerView.isHidden = true
        panel.makeFirstResponder(searchField)
        if searchField.stringValue.isEmpty { showHistory() } else { runSearch(searchField.stringValue) }
    }

    private func showDetail(_ word: String) {
        record(word)
        currentWord = word
        showingDetail = true

        IPAStore.shared.loadIfNeeded()
        let uk = IPAStore.shared.british(word) ?? ""
        let us = IPAStore.shared.american(word) ?? ""
        ukIPA.stringValue = uk.isEmpty ? "—" : uk
        usIPA.stringValue = us.isEmpty ? "—" : us
        ukRow.isHidden = false
        usRow.isHidden = false

        let html = Catalog.shared.article(for: word)
        let page = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body { margin: 6px 18px 24px; font: 15px/1.6 -apple-system, "Helvetica Neue", sans-serif; }
        .lex-dict { font-size: 12px; letter-spacing: .06em; text-transform: uppercase; opacity: .45; margin: 18px 0 8px; }
        .lex-section { border-top: 1px solid rgba(127,127,127,.18); padding-top: 8px; }
        .lex-body img { max-width: 100%; height: auto; }
        a { color: #0a66ff; }
        </style></head><body>
        \(html)
        </body></html>
        """
        webView.loadHTMLString(page, baseURL: nil)
        scrollView.isHidden = true
        searchBox.isHidden = true
        profileBar.isHidden = true
        statusLabel.isHidden = false
        webView.isHidden = false
        backButton.isHidden = false
        headerView.isHidden = uk.isEmpty && us.isEmpty
        panel.makeFirstResponder(webView)
    }

    func openHistory(profileIndex: Int) {
        guard Catalog.shared.profiles.indices.contains(profileIndex) else { return }
        selectedProfile = profileIndex
        Catalog.shared.switchProfile(profileIndex)
        updateProfileSelection()
        searchField.stringValue = ""
        show()
        showHistory()
    }

    func open(word: String) {
        searchField.stringValue = word
        showDetail(word)
    }

    private func handleEscape() {
        if showingDetail {
            goBack()
        } else if !searchField.stringValue.isEmpty {
            searchField.stringValue = ""
            showHistory()
        } else {
            hide()
        }
    }

    @objc private func goBack() {
        webView.loadHTMLString("", baseURL: nil)
        searchField.stringValue = ""
        showList()
    }

    @objc private func speakCurrent(_ sender: NSButton) {
        guard !currentWord.isEmpty else { return }
        var language = sender.identifier?.rawValue ?? "en-GB"
        if language == "en-GB", (Catalog.shared.currentProfile?.name.uppercased().contains("FR") ?? false) {
            language = "fr-FR"
        }
        speak(currentWord, language: language)
    }

    private func speak(_ word: String, language: String) {
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }



    @objc private func openSelection() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard results.indices.contains(row) else { return }
        showDetail(results[row].word)
    }

    private func refreshAfterLoad() {
        rebuildProfileControl()
        let text = searchField.stringValue
        if text.isEmpty { showHistory() } else { runSearch(text) }
        updateStatus()
    }

    private func runSearch(_ text: String) {
        searchGeneration &+= 1
        let generation = searchGeneration
        Catalog.shared.search(prefix: text) { [weak self] hits in
            guard let self, generation == self.searchGeneration else { return }
            self.results = hits.map { (word: $0.0, dict: $0.1) }
            self.tableView.reloadData()
            if !self.results.isEmpty { self.tableView.selectRowIndexes([0], byExtendingSelection: false) }
        }
    }

    private func updateStatus() {
        let loaded = Catalog.shared.loadedCount
        let total = Catalog.shared.totalCount
        statusLabel.stringValue = "\(loaded)/\(total) " + (total == 1 ? "dict loaded" : "dicts loaded")
    }

    // MARK: - History

    private func history() -> [String] {
        UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    private func record(_ word: String) {
        guard !word.isEmpty else { return }
        var items = history().filter { $0 != word }
        items.insert(word, at: 0)
        if items.count > 100 { items = Array(items.prefix(100)) }
        UserDefaults.standard.set(items, forKey: historyKey)
        HistoryStore.shared.record(word, profile: Catalog.shared.currentProfile?.name ?? "default")
    }

    private func showHistory() {
        let items = history()
        results = items.map { (word: $0, dict: "") }
        tableView.reloadData()
        if !items.isEmpty { tableView.selectRowIndexes([0], byExtendingSelection: false) }
        updateStatus()
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        let text = searchField.stringValue
        if text.isEmpty { showHistory() } else { runSearch(text) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1); return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1); return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelection(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            handleEscape(); return true
        default:
            return false
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let next = max(0, min(results.count - 1, tableView.selectedRow + delta))
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        LexiqueRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let item = results[row]
        cell.textField?.attributedStringValue = NSAttributedString(
            string: item.word,
            attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor]
        )
        cell.toolTip = item.dict.isEmpty ? nil : item.dict
        return cell
    }

    // MARK: - WebView links

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.scheme == "entry" {
            let word = url.absoluteString.replacingOccurrences(of: "entry://", with: "")
                .removingPercentEncoding ?? ""
            if !word.isEmpty { showDetail(word) }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
