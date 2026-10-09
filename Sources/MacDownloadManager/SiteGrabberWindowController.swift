import AppKit
import DownloadCore
import UniformTypeIdentifiers

@MainActor final class SiteGrabberWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let onAddDownloads: ([URL], URL, Bool) -> Void
    private var allItems: [GrabbedItem] = []
    private var displayItems: [GrabbedItem] = []
    private var selectedURLs: Set<URL> = []
    private var activeCategory = "All"
    private var destinationURL: URL

    private struct QuickSite {
        let title: String
        let urlString: String
    }

    private let quickSites: [QuickSite] = [
        QuickSite(title: "Choose Website… (or enter URL)", urlString: ""),
        QuickSite(title: "Node.js Dist (Official releases & binaries)", urlString: "https://nodejs.org/dist/"),
        QuickSite(title: "Python Downloads (Official Python installers & packages)", urlString: "https://www.python.org/downloads/"),
        QuickSite(title: "Internet Archive (Software library)", urlString: "https://archive.org/details/software"),
        QuickSite(title: "Linux Mint Releases (ISOs and packages)", urlString: "https://www.linuxmint.com/download.php"),
        QuickSite(title: "Ubuntu Cloud Images (Daily & release server ISOs)", urlString: "https://cloud-images.ubuntu.com/releases/"),
        QuickSite(title: "Apple Open Source (Official tarballs & headers)", urlString: "https://opensource.apple.com/"),
        QuickSite(title: "W3C Media Samples (HTML5 audio & video test files)", urlString: "https://www.w3schools.com/html/html5_video.asp"),
        QuickSite(title: "Git for Windows Releases (Binaries & packages)", urlString: "https://github.com/git-for-windows/git/releases")
    ]

    private let urlField = NSTextField()
    private let sitePopup = NSPopUpButton()
    private let presetPopup = NSPopUpButton()
    private let grabButton = NSButton(title: "Start Grab", target: nil, action: nil)
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "Enter a web address or choose a website below to find files.")

    private let categoryFilter = NSSegmentedControl()
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let selectionSummaryLabel = NSTextField(labelWithString: "No files found")
    private let pathLabel = NSTextField(labelWithString: "")
    private let downloadButton = NSButton(title: "Download Now", target: nil, action: nil)
    private let queueButton = NSButton(title: "Add to Queue", target: nil, action: nil)

    init(onAddDownloads: @escaping ([URL], URL, Bool) -> Void) {
        self.onAddDownloads = onAddDownloads
        self.destinationURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Site Grabber — MacDownloadManager"
        window.minSize = NSSize(width: 760, height: 500)
        window.center()
        super.init(window: window)

        configureUI()
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if urlField.stringValue.isEmpty,
           let paste = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           paste.lowercased().hasPrefix("http://") || paste.lowercased().hasPrefix("https://") {
            urlField.stringValue = paste
        }
    }
    
    func updateAppearance(_ appearance: InterfaceAppearance) {
        window?.appearance = appearance.appKit
        window?.backgroundColor = appearance.windowBackground
        tableView.backgroundColor = appearance.tableBackground
        window?.contentView?.needsDisplay = true
    }

    private func configureUI() {
        guard let window, let content = window.contentView else { return }

        // Top Section: Header & URL Input (IDM Classic Look)
        let globeIcon = NSImageView(image: AppTheme.classicIcon("grabber") ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!)
        globeIcon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        globeIcon.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let titleLabel = NSTextField(labelWithString: "Site Grabber")
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        let subtitleLabel = NSTextField(labelWithString: "Explore any web page and download all pictures, video, audio, or files.")
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        let headerText = NSStackView(views: [titleLabel, subtitleLabel])
        headerText.orientation = .vertical; headerText.alignment = .leading; headerText.spacing = 2

        let headerStack = NSStackView(views: [globeIcon, headerText])
        headerStack.spacing = 10; headerStack.alignment = .centerY

        // Input controls
        let addressCaption = NSTextField(labelWithString: "Address:")
        addressCaption.font = .systemFont(ofSize: 12, weight: .medium)
        addressCaption.widthAnchor.constraint(equalToConstant: 65).isActive = true

        urlField.placeholderString = "https://example.com/page (or choose a website below)"
        urlField.target = self; urlField.action = #selector(startGrab)
        let pasteBtn = NSButton(title: "Paste", target: self, action: #selector(pasteURL))
        pasteBtn.bezelStyle = .rounded; pasteBtn.controlSize = .small

        let visitBtn = NSButton(title: "Visit Site", target: self, action: #selector(openCurrentSiteInBrowser))
        visitBtn.bezelStyle = .rounded; visitBtn.controlSize = .small
        visitBtn.toolTip = "Open this web address in your default web browser"

        let urlRow = NSStackView(views: [addressCaption, urlField, pasteBtn, visitBtn])
        urlRow.alignment = .centerY; urlRow.spacing = 8
        urlField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let siteCaption = NSTextField(labelWithString: "Website:")
        siteCaption.font = .systemFont(ofSize: 12, weight: .medium)
        siteCaption.widthAnchor.constraint(equalToConstant: 65).isActive = true

        sitePopup.removeAllItems()
        for s in quickSites { sitePopup.addItem(withTitle: s.title) }
        sitePopup.target = self; sitePopup.action = #selector(sitePopupChanged)
        sitePopup.controlSize = .small

        let presetCaption = NSTextField(labelWithString: "Template:")
        presetCaption.font = .systemFont(ofSize: 12, weight: .medium)

        presetPopup.removeAllItems()
        presetPopup.addItems(withTitles: [
            "All files on the web site",
            "Pictures & Images (JPG, PNG, WebP, GIF, SVG)",
            "Video files (MP4, MKV, MOV, WebM, AVI)",
            "Audio files (MP3, FLAC, WAV, M4A, AAC)",
            "Compressed Archives (ZIP, RAR, 7Z, DMG, PKG)",
            "Documents (PDF, DOCX, TXT, EPUB, CSV)"
        ])
        presetPopup.target = self; presetPopup.action = #selector(presetChanged)
        presetPopup.controlSize = .small

        grabButton.title = "Start Grab"
        grabButton.target = self; grabButton.action = #selector(startGrab)
        grabButton.bezelStyle = .rounded
        grabButton.keyEquivalent = "\r"

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false

        let controlRow = NSStackView(views: [siteCaption, sitePopup, presetCaption, presetPopup, NSView(), progressIndicator, grabButton])
        controlRow.alignment = .centerY; controlRow.spacing = 8

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let inputCard = NSStackView(views: [headerStack, urlRow, controlRow, statusLabel])
        inputCard.orientation = .vertical; inputCard.alignment = .leading; inputCard.spacing = 8
        inputCard.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 12, right: 16)

        // Middle Section: Filter Bar & Table
        categoryFilter.segmentCount = 6
        categoryFilter.setLabel("All", forSegment: 0)
        categoryFilter.setLabel("Pictures", forSegment: 1)
        categoryFilter.setLabel("Video", forSegment: 2)
        categoryFilter.setLabel("Audio", forSegment: 3)
        categoryFilter.setLabel("Compressed", forSegment: 4)
        categoryFilter.setLabel("Documents", forSegment: 5)
        categoryFilter.selectedSegment = 0
        categoryFilter.target = self; categoryFilter.action = #selector(categoryChanged)
        categoryFilter.controlSize = .small

        searchField.placeholderString = "Filter files..."
        searchField.target = self; searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let selectAllBtn = NSButton(title: "Select All", target: self, action: #selector(selectAllItems))
        selectAllBtn.bezelStyle = .rounded; selectAllBtn.controlSize = .small
        let unselectAllBtn = NSButton(title: "Unselect All", target: self, action: #selector(unselectAllItems))
        unselectAllBtn.bezelStyle = .rounded; unselectAllBtn.controlSize = .small

        let filterBar = NSStackView(views: [categoryFilter, NSView(), searchField, selectAllBtn, unselectAllBtn])
        filterBar.alignment = .centerY; filterBar.spacing = 8
        filterBar.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)

        // Table
        tableView.dataSource = self; tableView.delegate = self
        tableView.rowHeight = 28
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.usesAlternatingRowBackgroundColors = true

        let colCheck = NSTableColumn(identifier: .init("check")); colCheck.title = "✓"; colCheck.width = 30; colCheck.minWidth = 26
        let colName = NSTableColumn(identifier: .init("name")); colName.title = "File Name"; colName.width = 280; colName.minWidth = 140
        let colCategory = NSTableColumn(identifier: .init("category")); colCategory.title = "Category"; colCategory.width = 90; colCategory.minWidth = 70
        let colExt = NSTableColumn(identifier: .init("ext")); colExt.title = "Type"; colExt.width = 50; colExt.minWidth = 40
        let colURL = NSTableColumn(identifier: .init("url")); colURL.title = "Web Link"; colURL.width = 360; colURL.minWidth = 180

        for c in [colCheck, colName, colCategory, colExt, colURL] {
            c.resizingMask = [.autoresizingMask, .userResizingMask]
            tableView.addTableColumn(c)
        }

        let tableScroll = NSScrollView()
        tableScroll.documentView = tableView
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true

        // Bottom Section: Summary, Destination & Actions
        selectionSummaryLabel.font = .systemFont(ofSize: 11, weight: .medium)
        selectionSummaryLabel.textColor = .secondaryLabelColor

        let saveCaption = NSTextField(labelWithString: "Save to:")
        saveCaption.font = .systemFont(ofSize: 11, weight: .medium)
        pathLabel.stringValue = destinationURL.path
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240).isActive = true

        let browseBtn = NSButton(title: "Browse…", target: self, action: #selector(browseDestination))
        browseBtn.bezelStyle = .rounded; browseBtn.controlSize = .small

        let saveStack = NSStackView(views: [saveCaption, pathLabel, browseBtn])
        saveStack.spacing = 6; saveStack.alignment = .centerY

        let closeBtn = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        closeBtn.bezelStyle = .rounded

        queueButton.target = self; queueButton.action = #selector(addSelectedToQueue)
        queueButton.bezelStyle = .rounded; queueButton.isEnabled = false

        downloadButton.target = self; downloadButton.action = #selector(downloadSelectedNow)
        downloadButton.bezelStyle = .rounded
        downloadButton.isEnabled = false

        let bottomActions = NSStackView(views: [selectionSummaryLabel, NSView(), saveStack, queueButton, downloadButton, closeBtn])
        bottomActions.alignment = .centerY; bottomActions.spacing = 8
        bottomActions.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 12, right: 16)

        // Assemble Root Layout
        let sep1 = NSBox(); sep1.boxType = .separator
        let sep2 = NSBox(); sep2.boxType = .separator

        let root = NSStackView(views: [inputCard, sep1, filterBar, tableScroll, sep2, bottomActions])
        root.orientation = .vertical; root.spacing = 0; root.alignment = .leading
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        for v in [inputCard, sep1, filterBar, tableScroll, sep2, bottomActions] {
            v.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    @objc private func sitePopupChanged() {
        let idx = sitePopup.indexOfSelectedItem
        guard quickSites.indices.contains(idx), !quickSites[idx].urlString.isEmpty else { return }
        let site = quickSites[idx]
        urlField.stringValue = site.urlString
        startGrab()
    }

    @objc private func openCurrentSiteInBrowser() {
        var text = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        if let url = URL(string: text) {
            NSWorkspace.shared.open(url)
        }
    }

    func grab(url: URL) {
        urlField.stringValue = url.absoluteString
        startGrab()
    }

    @objc private func pasteURL() {
        if let pasteboardString = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !pasteboardString.isEmpty {
            urlField.stringValue = pasteboardString
        }
    }

    @objc private func startGrab() {
        var text = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusLabel.stringValue = "Please enter a web address or choose a website from the dropdown."
            return
        }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
            urlField.stringValue = text
        }
        guard let url = URL(string: text), url.host != nil else {
            statusLabel.stringValue = "Invalid website address."
            return
        }

        grabButton.isEnabled = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "Connecting to \(url.host ?? text)..."

        Task { [weak self] in
            do {
                let items = try await SiteGrabber.items(on: url)
                self?.handleGrabSuccess(items: items)
            } catch {
                self?.handleGrabFailure(error: error)
            }
        }
    }

    private func handleGrabSuccess(items: [GrabbedItem]) {
        progressIndicator.stopAnimation(nil)
        grabButton.isEnabled = true
        allItems = items
        selectedURLs = Set(items.map(\.url)) // Selected by default
        if items.isEmpty {
            statusLabel.stringValue = "Scan complete. No downloadable files detected on this page."
        } else {
            statusLabel.stringValue = "Scan complete. Found \(items.count) downloadable files."
        }
        applyFilters()
    }

    private func handleGrabFailure(error: Error) {
        progressIndicator.stopAnimation(nil)
        grabButton.isEnabled = true
        statusLabel.stringValue = "Failed to grab site: \(error.localizedDescription)"
        let alert = NSAlert(error: error)
        alert.messageText = "Site Grabber Error"
        alert.informativeText = "Unable to find downloadable files on this page: \(error.localizedDescription)"
        alert.runModal()
    }

    @objc private func presetChanged() {
        let index = presetPopup.indexOfSelectedItem
        switch index {
        case 1: categoryFilter.selectedSegment = 1
        case 2: categoryFilter.selectedSegment = 2
        case 3: categoryFilter.selectedSegment = 3
        case 4: categoryFilter.selectedSegment = 4
        case 5: categoryFilter.selectedSegment = 5
        default: categoryFilter.selectedSegment = 0
        }
        categoryChanged()
    }

    @objc private func categoryChanged() {
        let labels = ["All", "Picture", "Video", "Audio", "Compressed", "Document"]
        let idx = categoryFilter.selectedSegment
        activeCategory = idx >= 0 && idx < labels.count ? labels[idx] : "All"
        applyFilters()
    }

    @objc private func searchChanged() {
        applyFilters()
    }

    private func applyFilters() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        displayItems = allItems.filter { item in
            let matchesCategory = activeCategory == "All" || item.category == activeCategory
            let matchesQuery = query.isEmpty || item.filename.lowercased().contains(query) || item.url.absoluteString.lowercased().contains(query)
            return matchesCategory && matchesQuery
        }

        tableView.reloadData()
        updateSummary()
    }

    @objc private func selectAllItems() {
        for item in displayItems { selectedURLs.insert(item.url) }
        tableView.reloadData()
        updateSummary()
    }

    @objc private func unselectAllItems() {
        for item in displayItems { selectedURLs.remove(item.url) }
        tableView.reloadData()
        updateSummary()
    }

    private func updateSummary() {
        let count = selectedURLs.count
        selectionSummaryLabel.stringValue = "Selected \(count) of \(allItems.count) files"
        downloadButton.isEnabled = count > 0
        queueButton.isEnabled = count > 0
    }

    @objc private func browseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = destinationURL
        if panel.runModal() == .OK, let url = panel.url {
            destinationURL = url
            pathLabel.stringValue = url.path
        }
    }

    @objc private func downloadSelectedNow() {
        commitDownloads(startImmediately: true)
    }

    @objc private func addSelectedToQueue() {
        commitDownloads(startImmediately: false)
    }

    private func commitDownloads(startImmediately: Bool) {
        let selectedList = allItems.filter { selectedURLs.contains($0.url) }.map(\.url)
        guard !selectedList.isEmpty else { return }
        onAddDownloads(selectedList, destinationURL, startImmediately)
        window?.close()
    }

    @objc private func closeWindow() {
        window?.close()
    }

    // Table View Data Source & Delegate
    func numberOfRows(in tableView: NSTableView) -> Int {
        displayItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard displayItems.indices.contains(row) else { return nil }
        let item = displayItems[row]
        let isSelected = selectedURLs.contains(item.url)

        switch tableColumn?.identifier.rawValue {
        case "check":
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRowCheck(_:)))
            checkbox.state = isSelected ? .on : .off
            checkbox.tag = row
            return checkbox

        case "name":
            let iconView = NSImageView(image: NSWorkspace.shared.icon(for: UTType(filenameExtension: item.url.pathExtension) ?? .data))
            iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
            iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true
            let label = NSTextField(labelWithString: item.filename)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.lineBreakMode = .byTruncatingMiddle
            label.toolTip = item.filename
            let stack = NSStackView(views: [iconView, label])
            stack.spacing = 6; stack.alignment = .centerY
            return stack

        case "category":
            let badge = NSTextField(labelWithString: item.category)
            badge.font = .systemFont(ofSize: 11, weight: .regular)
            badge.textColor = .secondaryLabelColor
            return badge

        case "ext":
            let extLabel = NSTextField(labelWithString: item.fileExtension.uppercased())
            extLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
            extLabel.textColor = .tertiaryLabelColor
            return extLabel

        case "url":
            let urlLabel = NSTextField(labelWithString: item.url.absoluteString)
            urlLabel.font = .systemFont(ofSize: 11)
            urlLabel.textColor = .secondaryLabelColor
            urlLabel.lineBreakMode = .byTruncatingMiddle
            urlLabel.toolTip = item.url.absoluteString
            return urlLabel

        default:
            return nil
        }
    }

    @objc private func toggleRowCheck(_ sender: NSButton) {
        let row = sender.tag
        guard displayItems.indices.contains(row) else { return }
        let item = displayItems[row]
        if sender.state == .on {
            selectedURLs.insert(item.url)
        } else {
            selectedURLs.remove(item.url)
        }
        updateSummary()
    }
}
