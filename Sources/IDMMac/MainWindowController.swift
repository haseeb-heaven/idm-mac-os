import AppKit
import IDMCore
import UniformTypeIdentifiers
import CryptoKit

@MainActor final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSToolbarDelegate, NSToolbarItemValidation {
    var browserIntegration: BrowserIntegrationCoordinator?
    var browserQAReportURL: URL?
    private let store: JobStore
    private let engine: DownloadEngine
    private var jobs: [DownloadJob]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var options = DownloadOptions()
    private let table = NSTableView()
    private let categories = NSOutlineView()
    private var categoryFilter = "All Downloads"
    private var storageError: String?
    private let status = NSTextField(labelWithString: "Ready")
    private let emptyTitle = NSTextField(labelWithString:"No downloads yet")
    private var emptyGroup:NSStackView?
    private let failureLabel = NSTextField(wrappingLabelWithString:"")
    private let failureStrip = NSStackView()
    private let failureRetry = NSButton(title:"Retry Download",target:nil,action:nil)
    private var timer: Timer?
    private var runningQueue = true
    private var detailsController: DownloadDetailsController?
    private var lastPersist = Date.distantPast
    private var progressTimes: [UUID: (Date, Int64, Double)] = [:]

    init(storageDirectory: URL? = nil) throws {
        let support = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IDMMac")
        store = try JobStore(url: support.appendingPathComponent("downloads.sqlite"))
        engine = DownloadEngine(workDirectory: support.appendingPathComponent("partials"))
        jobs = try store.load()
        if storageDirectory == nil,let data = UserDefaults.standard.data(forKey: "downloadOptions"), let saved = try? JSONDecoder().decode(DownloadOptions.self, from: data) { options = saved }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named:.aqua);window.backgroundColor = .windowBackgroundColor;window.title = "Internet Download Manager"; window.center(); window.minSize = NSSize(width: 900, height: 500)
        super.init(window: window)
        configureMenu(); configureContent()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pumpQueue(); self?.updateStatus() }
        }
    }

    func queueBrowserDownload(link:BrowserLink,destination:URL) throws -> UUID {
        try queueBrowserDownloads(links:[link],destinations:[destination])[0]
    }
    func queueBrowserDownloads(links:[BrowserLink],destinations:[URL]) throws -> [UUID] {
        guard !links.isEmpty, links.count == destinations.count, Set(destinations).count == destinations.count else { throw BrowserProtocolError.invalid }
        var additions:[DownloadJob] = []
        do {
            for (link,destination) in zip(links,destinations) {
                try link.validate()
                guard !jobs.contains(where:{$0.destination == destination}), !FileManager.default.fileExists(atPath:destination.path) else { throw DownloadError.destinationExists }
                let job = try DownloadJob(url:URL(string:link.url)!,destination:destination)
                additions.append(job)
                try CredentialStore.saveHeaders(link.headers ?? [:],jobID:job.id)
            }
            try store.save(jobs + additions)
        } catch { for job in additions { try? CredentialStore.deleteHeaders(jobID:job.id) }; throw error }
        jobs += additions; writeBrowserQAReport(); refresh(); pumpQueue(); return additions.map(\.id)
    }
    func beginBrowserImport(link:BrowserLink,destination:URL) throws -> UUID {
        try link.validate(allowBlob:true)
        guard !jobs.contains(where:{$0.destination == destination}) else { throw DownloadError.destinationExists }
        guard link.url.hasPrefix("blob:"), let page = link.pageURL.flatMap(URL.init(string:)) else { throw BrowserProtocolError.invalid }
        var job = try DownloadJob(url:page,destination:destination)
        job.browserSourceURL = URL(string:link.url); job.state = .downloading
        try store.save(jobs + [job]); jobs.append(job); writeBrowserQAReport(); refresh(); return job.id
    }
    func browserImportProgress(id:UUID,received:Int64,total:Int64) { update(id,TransferProgress(received:received,total:total)); writeBrowserQAReport() }
    func browserImportFinished(id:UUID,error:Error?) { finished(id,error:error) }
    private func writeBrowserQAReport() {
        guard let browserQAReportURL else { return }
        let report = jobs.map { ["id":$0.id.uuidString,"state":$0.state.rawValue,"destination":$0.destination.path,"receivedBytes":$0.receivedBytes,"totalBytes":$0.totalBytes] as [String:Any] }
        if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:browserQAReportURL,options:.atomic) }
    }
    @objc private func browserSetup() {
        let alert = NSAlert(); alert.messageText = "Browser Integrations"
        alert.informativeText = "Register the native host, then load the included Chromium or Firefox extension. Safari and other browsers can use the HTTP link bookmarklet. Automatic capture and session cookies are off until enabled in the extension."
        alert.addButton(withTitle:"Register Browsers"); alert.addButton(withTitle:"Open Setup"); alert.addButton(withTitle:"Cancel")
        let result = alert.runModal()
        do {
            if result == .alertFirstButtonReturn { try BrowserRegistration.install(app:Bundle.main.bundleURL) }
            if result == .alertFirstButtonReturn || result == .alertSecondButtonReturn, let resources = Bundle.main.resourceURL { NSWorkspace.shared.open(resources.appendingPathComponent("BrowserIntegration/setup.html")) }
        } catch { self.alert(error) }
    }
    func smokeCheck(output:URL) throws -> [String:Any] {
        guard let window, window.isVisible, let content = window.contentView else { throw DownloadError.storage("Main window is not visible") }
        content.layoutSubtreeIfNeeded();window.displayIfNeeded()
        guard table.tableColumns.count == 6, categories.numberOfRows >= 5, table.dataSource != nil, table.delegate != nil else { throw DownloadError.storage("Download controls are not configured") }
        let frameView = content.superview ?? content
        if let bitmap = frameView.bitmapImageRepForCachingDisplay(in:frameView.bounds) {
            frameView.cacheDisplay(in:frameView.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])?.write(to:output.deletingPathExtension().appendingPathExtension("png"))
        }
        let defaultFrame = window.frame
        window.setContentSize(NSSize(width:900,height:500));content.layoutSubtreeIfNeeded();frameView.layoutSubtreeIfNeeded();window.displayIfNeeded()
        if let bitmap = frameView.bitmapImageRepForCachingDisplay(in:frameView.bounds) {
            frameView.cacheDisplay(in:frameView.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])?.write(to:output.deletingLastPathComponent().appendingPathComponent("ui-minimum.png"))
        }
        guard table.enclosingScrollView?.bounds.width ?? 0 > 500, categories.bounds.width >= 150 else { throw DownloadError.storage("Content is clipped at minimum width") }
        window.setFrame(defaultFrame,display:true)
        let scheduled = try DownloadJob(url:URL(string:"https://example.com/scheduled")!,destination:output.deletingLastPathComponent().appendingPathComponent("scheduled.bin"),scheduledAt:Date().addingTimeInterval(3600))
        jobs.append(scheduled);prepareForTermination()
        guard let saved = try store.load().first(where:{$0.id == scheduled.id}), saved.state == .queued, saved.scheduledAt == scheduled.scheduledAt else { throw DownloadError.storage("Quit changed scheduled job") }
        jobs.removeAll(where:{$0.id == scheduled.id});try store.save(jobs)
        return ["scheduledQuitCheck":true,"windowNumber":window.windowNumber,"toolbarItems":window.toolbar?.items.count ?? 0,"minimumWidthChecked":900,"visible":window.isVisible,"columns":table.tableColumns.count,"categoryRows":categories.numberOfRows,"width":window.frame.width,"height":window.frame.height]
    }
    func endToEndCheck(base:URL,output:URL) async throws -> [String:Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("idm-ui-transfer-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        options = DownloadOptions()
        options.bytesPerSecond = 512*1024;options.chunkBytes = 256*1024
        addBatch([base.appendingPathComponent("slow").absoluteString],directory:directory)
        guard let id = jobs.last?.id else { throw DownloadError.storage("UI did not create job") }
        table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        let deadline = Date().addingTimeInterval(45)
        while jobs.first(where:{$0.id == id})?.receivedBytes == 0 {
            guard Date() < deadline else { throw DownloadError.storage("UI transfer did not start") }
            try await Task.sleep(for:.milliseconds(50))
        }
        stop()
        while tasks[id] != nil { try await Task.sleep(for:.milliseconds(50)) }
        guard jobs.first(where:{$0.id == id})?.state == .paused else { throw DownloadError.storage("Stop did not pause job: state=\(jobs.first(where:{$0.id == id})?.state.rawValue ?? "missing"), selected=\(selected?.id == id)") }
        resume()
        while tasks[id] != nil || jobs.first(where:{$0.id == id})?.state == .queued {
            guard Date() < deadline else { throw DownloadError.storage("UI resume timed out") }
            try await Task.sleep(for:.milliseconds(50))
        }
        guard let complete = jobs.first(where:{$0.id == id}),complete.state == .completed else { throw DownloadError.storage("UI download did not complete") }
        let data = try Data(contentsOf:complete.destination)
        guard SHA256.hash(data:data) == SHA256.hash(data:Data((0..<1048576).map { UInt8($0%256) })) else { throw DownloadError.incomplete }
        if let column = table.tableColumns.first(where:{$0.identifier.rawValue == "progress"}),
           let cell = self.tableView(table,viewFor:column,row:0),let bar = cell.subviews.first as? NSProgressIndicator {
            guard !bar.isIndeterminate,bar.doubleValue == 100 else { throw DownloadError.storage("Completed progress bar is incorrect") }
        } else { throw DownloadError.storage("Progress cell missing") }
        showProgress();detailsController?.close()
        addBatch([base.appendingPathComponent("protected").absoluteString],directory:directory)
        guard let failedID = jobs.last?.id else { throw DownloadError.storage("UI failed job missing") }
        while tasks[failedID] != nil || jobs.last?.state == .queued {
            guard Date() < deadline else { throw DownloadError.storage("UI error test timed out") }
            try await Task.sleep(for:.milliseconds(50))
        }
        table.selectRowIndexes(IndexSet(integer:jobs.count-1),byExtendingSelection:false);refresh()
        guard jobs.last?.state == .failed,!failureStrip.isHidden,failureRetry.isEnabled else { throw DownloadError.storage("UI error actions unavailable") }
        window?.contentView?.layoutSubtreeIfNeeded();window?.displayIfNeeded()
        if let frame = window?.contentView?.superview,let bitmap = frame.bitmapImageRepForCachingDisplay(in:frame.bounds) {
            frame.cacheDisplay(in:frame.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])?.write(to:output.deletingPathExtension().appendingPathExtension("png"))
        }
        return ["actualDownloadSHA256":true,"toolbarPauseResume":true,"completedDetails":true,"browserVerificationActions":true,"lightTheme":window?.effectiveAppearance.name.rawValue ?? "unknown"]
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    private var visible: [DownloadJob] {
        let filter = categoryFilter
        return jobs.filter { job in
            switch filter {
            case "All Downloads": true
            case "Unfinished": job.state != .completed
            case "Finished": job.state == .completed
            case "Main Queue", "Queues": job.state == .queued
            case "Grabber projects": false
            default: job.category == filter
            }
        }
    }
    private var selected: DownloadJob? { let row = table.selectedRow; return visible.indices.contains(row) ? visible[row] : nil }
    private var toolbarActions: [(String,String,String,Selector)] {
        [("add","Add URL","plus.circle",#selector(addURL)),("resume","Resume","play.fill",#selector(resume)),
         ("stop","Stop","pause.fill",#selector(stop)),("stopAll","Stop All","pause.circle",#selector(stopAll)),
         ("delete","Delete","trash",#selector(deleteJob)),("details","Details","info.circle",#selector(showProgress)),
         ("options","Options","gearshape",#selector(showOptions)),("schedule","Scheduler","clock",#selector(schedule)),
         ("startQueue","Start Queue","play.rectangle",#selector(startQueue)),("stopQueue","Stop Queue","stop.circle",#selector(stopQueue)),
         ("grabber","Grabber","link",#selector(grabber))]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar:NSToolbar) -> [NSToolbarItem.Identifier] { toolbarActions.map { .init($0.0) } }
    func toolbarAllowedItemIdentifiers(_ toolbar:NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar:NSToolbar,itemForItemIdentifier identifier:NSToolbarItem.Identifier,willBeInsertedIntoToolbar:Bool) -> NSToolbarItem? {
        guard let (_,title,symbol,action) = toolbarActions.first(where:{$0.0 == identifier.rawValue}) else { return nil }
        let item = NSToolbarItem(itemIdentifier:identifier);item.label = title;item.paletteLabel = title;item.toolTip = title
        item.image = IDMTheme.icon(symbol,color:IDMTheme.color(identifier.rawValue));item.target = self;item.action = action
        item.visibilityPriority = ["add","resume","stop","details"].contains(identifier.rawValue) ? .high : .standard
        return item
    }
    func validateToolbarItem(_ item:NSToolbarItem) -> Bool {
        switch item.itemIdentifier.rawValue {
        case "resume": return selected.map { $0.state == .paused || $0.state == .failed } ?? false
        case "stop": return selected.map { $0.state == .downloading || $0.state == .queued } ?? false
        case "delete", "details": return selected != nil
        case "schedule": return selected.map { $0.state != .completed && tasks[$0.id] == nil } ?? false
        case "stopAll": return !tasks.isEmpty || jobs.contains(where:{$0.state == .queued})
        case "startQueue": return !runningQueue && jobs.contains(where:{$0.state == .queued})
        case "stopQueue": return runningQueue
        default:return true
        }
    }
    private func configureMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About IDM Mac", action: #selector(about), keyEquivalent: "") .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit IDM Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(); menu.addItem(fileItem); fileItem.submenu = NSMenu(title: "File")
        fileItem.submenu?.addItem(withTitle: "Add URL…", action: #selector(addURL), keyEquivalent: "n").target = self
        fileItem.submenu?.addItem(withTitle: "Batch URLs…", action: #selector(batchURLs), keyEquivalent: "b").target = self
        fileItem.submenu?.addItem(withTitle: "Browser Integrations…", action: #selector(browserSetup), keyEquivalent: "").target = self
        let editItem = NSMenuItem(); menu.addItem(editItem); editItem.submenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editItem.submenu?.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }
    private func configureContent() {
        guard let content = window?.contentView else { return }
        let toolbar = NSToolbar(identifier:"IDMMac.MainToolbar");toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel;toolbar.sizeMode = .regular;toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar;window?.toolbarStyle = .expanded
        let categoryColumn = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("category"))
        categories.addTableColumn(categoryColumn); categories.outlineTableColumn = categoryColumn
        categories.focusRingType = .none; categories.headerView = nil; categories.rowHeight = 26; categories.dataSource = self; categories.delegate = self
        categories.reloadData(); categories.expandItem("All Downloads"); categories.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        categories.backgroundColor = .white;categories.selectionHighlightStyle = .regular
        categories.setAccessibilityLabel("Download categories")
        let categoryScroll = NSScrollView(); categoryScroll.documentView = categories; categoryScroll.hasVerticalScroller = true
        let sidebar = NSStackView(views: [NSTextField(labelWithString: "Categories"), categoryScroll])
        sidebar.orientation = .vertical; sidebar.alignment = .leading; sidebar.spacing = 12
        categoryScroll.widthAnchor.constraint(equalTo:sidebar.widthAnchor).isActive = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.backgroundColor = .white;table.gridStyleMask = [.solidHorizontalGridLineMask,.solidVerticalGridLineMask];table.gridColor = NSColor(white:0.93,alpha:1)
        table.usesAlternatingRowBackgroundColors = false; table.allowsMultipleSelection = false
        table.dataSource = self; table.delegate = self; table.rowHeight = 32
        table.target = self; table.doubleAction = #selector(showProgress)
        for (id, title, width) in [("name","File Name",260.0), ("size","Size",95.0), ("status","Status",100.0), ("progress","Progress",95.0), ("speed","Transfer Rate",110.0), ("date","Date Added",140.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width
            column.minWidth = ["name":180.0,"size":65.0,"status":80.0,"progress":65.0,"speed":95.0,"date":105.0][id] ?? 60
            column.resizingMask = [.autoresizingMask,.userResizingMask]
            table.addTableColumn(column)
        }
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        emptyTitle.font = .systemFont(ofSize:16,weight:.semibold)
        let hint = NSTextField(labelWithString:"Choose Add URL to start a download.");hint.textColor = .secondaryLabelColor
        let add = NSButton(title:"Add URL…",target:self,action:#selector(addURL));add.bezelStyle = .rounded
        let empty = NSStackView(views:[emptyTitle,hint,add]);empty.orientation = .vertical;empty.spacing = 12;empty.translatesAutoresizingMaskIntoConstraints = false;content.addSubview(empty)
        empty.isHidden = !visible.isEmpty;emptyGroup = empty
        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin; split.addArrangedSubview(sidebar); split.addArrangedSubview(scroll)
        failureLabel.textColor = .secondaryLabelColor;failureLabel.maximumNumberOfLines = 3
        failureRetry.target = self;failureRetry.action = #selector(resume);failureRetry.bezelStyle = .rounded
        let openPage = NSButton(title:"Open Website",target:self,action:#selector(openSelectedPage));openPage.bezelStyle = .rounded
        failureStrip.setViews([failureLabel,failureRetry,openPage],in:.leading);failureStrip.orientation = .horizontal;failureStrip.spacing = 12;failureStrip.isHidden = true
        failureLabel.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor;status.lineBreakMode = .byTruncatingTail
        let root = NSStackView(views: [split, failureStrip, status]); root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(root)
        for view in [split, failureStrip, status] { view.translatesAutoresizingMaskIntoConstraints = false; view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),root.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),sidebar.widthAnchor.constraint(equalToConstant: 185)])
        content.addSubview(empty,positioned:.above,relativeTo:root)
        NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo:scroll.centerXAnchor),empty.centerYAnchor.constraint(equalTo:scroll.centerYAnchor)])
        table.setAccessibilityLabel("Downloads")
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return 5 }
        if item as? String == "All Downloads" { return 6 }
        if item as? String == "Queues" { return 1 }
        return 0
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return ["All Downloads", "Unfinished", "Finished", "Grabber projects", "Queues"][index] }
        if item as? String == "Queues" { return "Main Queue" }
        return ["Compressed", "Documents", "Music", "Programs", "Video", "Other"][index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { outlineView.numberOfChildren(ofItem:item) > 0 }
    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? { item }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard categories.selectedRow >= 0, let item = categories.item(atRow:categories.selectedRow) as? String else { return }
        categoryFilter = item; refresh()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard visible.indices.contains(row) else { return nil }; let job = visible[row]
        switch tableColumn?.identifier.rawValue {
        case "name": return job.destination.lastPathComponent
        case "size": return job.totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: job.totalBytes, countStyle: .file) : "Unknown"
        case "status": return job.state.rawValue.capitalized
        case "progress": return job.state == .completed ? "100%" : job.totalBytes > 0 ? String(format: "%.1f%%", Double(job.receivedBytes) / Double(job.totalBytes) * 100) : "—"
        case "speed": return job.state == .downloading ? ByteCountFormatter.string(fromByteCount: Int64(progressTimes[job.id]?.2 ?? 0), countStyle: .file) + "/s" : "—"
        case "date": return job.createdAt.formatted(date: .numeric, time: .omitted)
        default: return nil
        }
    }
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any) -> NSView? {
        guard let title = item as? String else { return nil }
        let icon = NSImageView();icon.image = IDMTheme.icon(IDMTheme.categorySymbol(title),color:IDMTheme.color(title),size:15)
        icon.widthAnchor.constraint(equalToConstant:18).isActive = true
        let label = NSTextField(labelWithString:title);label.font = .systemFont(ofSize:12);label.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views:[icon,label]);stack.spacing = 6;stack.alignment = .centerY
        return stack
    }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        guard visible.indices.contains(row), let column = tableColumn else { return nil }
        let job = visible[row]
        if column.identifier.rawValue == "progress" {
            let progress = NSProgressIndicator();progress.isIndeterminate = false;progress.style = .bar;progress.minValue = 0;progress.maxValue = 100
            progress.doubleValue = job.state == .completed ? 100 : job.totalBytes > 0 ? min(100,Double(job.receivedBytes)/Double(job.totalBytes)*100) : 0
            progress.toolTip = self.tableView(tableView,objectValueFor:column,row:row) as? String
            let host = NSView();progress.translatesAutoresizingMaskIntoConstraints = false;host.addSubview(progress)
            NSLayoutConstraint.activate([progress.leadingAnchor.constraint(equalTo:host.leadingAnchor,constant:8),progress.trailingAnchor.constraint(equalTo:host.trailingAnchor,constant:-8),progress.centerYAnchor.constraint(equalTo:host.centerYAnchor)])
            return host
        }
        let text = self.tableView(tableView,objectValueFor:column,row:row) as? String ?? ""
        let label = NSTextField(labelWithString:text);label.font = .systemFont(ofSize:12);label.lineBreakMode = .byTruncatingMiddle;label.toolTip = text
        if column.identifier.rawValue == "status" { label.textColor = job.state == .failed ? .systemRed : job.state == .completed ? IDMTheme.green : .secondaryLabelColor }
        var views:[NSView] = [label]
        if column.identifier.rawValue == "name" {
            let icon = NSImageView();icon.image = NSWorkspace.shared.icon(for:UTType(filenameExtension:job.destination.pathExtension) ?? .data);icon.widthAnchor.constraint(equalToConstant:18).isActive = true;icon.heightAnchor.constraint(equalToConstant:18).isActive = true;views.insert(icon,at:0)
        }
        let stack = NSStackView(views:views);stack.spacing = 6;stack.alignment = .centerY;stack.edgeInsets = NSEdgeInsets(top:0,left:6,bottom:0,right:6)
        return stack
    }
    private func alert(_ error: Error) { NSAlert(error: error).runModal() }
    @discardableResult private func persist() -> Bool {
        do { try store.save(jobs); lastPersist = Date(); storageError = nil; writeBrowserQAReport(); return true } catch { runningQueue = false; storageError = error.localizedDescription; status.stringValue = error.localizedDescription; return false }
    }
    private func refresh() { let selectedID = selected?.id;emptyGroup?.isHidden = !visible.isEmpty;emptyTitle.stringValue = jobs.isEmpty ? "No downloads yet" : "No downloads in this category";table.reloadData();if let selectedID,let row = visible.firstIndex(where:{$0.id == selectedID}) { table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false) }; window?.toolbar?.validateVisibleItems(); updateStatus(); if let id = detailsController?.jobID, let job = jobs.first(where:{$0.id == id}) { detailsController?.update(job,speed:progressTimes[id]?.2 ?? 0) } }
    func tableViewSelectionDidChange(_ notification:Notification) { window?.toolbar?.validateVisibleItems();updateStatus() }
    @objc private func openSelectedPage() { if let job = selected { NSWorkspace.shared.open(job.url) } }
    private func updateStatus() {
        failureStrip.isHidden = selected?.error == nil
        failureLabel.stringValue = selected?.error ?? "";failureLabel.toolTip = selected?.error
        failureRetry.isEnabled = selected?.state == .failed || selected?.state == .paused
 if let job = selected, let error = job.error { status.stringValue = "Download failed · " + (job.url.host ?? "");status.toolTip = error;return }; if let storageError { status.stringValue = storageError; return }; status.stringValue = "\(jobs.count) downloads · \(tasks.count) active · Queue \(runningQueue ? "running" : "stopped")" }
    @objc private func filterChanged() { refresh() }
    @objc private func about() { let a = NSAlert(); a.messageText = "IDM Mac"; a.informativeText = "Personal native macOS download manager. Version 0.1. Feature parity research is ongoing."; a.runModal() }
    private func textField(_ placeholder: String, secure: Bool = false) -> NSTextField {
        let field: NSTextField = secure ? NSSecureTextField() : NSTextField(); field.placeholderString = placeholder
        field.widthAnchor.constraint(equalToConstant: 420).isActive = true; return field
    }
    @objc private func addURL() {
        let a = NSAlert(); a.messageText = "Add Download"; a.addButton(withTitle: "Download"); a.addButton(withTitle: "Cancel")
        let url = textField("https://example.com/file.zip"); let user = textField("Username (optional)"); let password = textField("Password (optional)", secure: true)
        let fields = NSStackView(views: [url,user,password]); fields.orientation = .vertical; fields.alignment = .leading;fields.spacing = 10;fields.frame.size = fields.fittingSize;a.accessoryView = fields
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do {
            guard let address = URL(string: url.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw DownloadError.invalidURL }
            let panel = NSSavePanel(); panel.nameFieldStringValue = DownloadFilename.from(address)
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            let job = try DownloadJob(url: address, destination: destination)
            guard !jobs.contains(where: { $0.destination == destination && $0.state != .completed }) else { throw DownloadError.destinationExists }
            if !user.stringValue.isEmpty { try CredentialStore.save(username: user.stringValue, password: password.stringValue, jobID: job.id) }
            jobs.append(job); persist(); refresh(); pumpQueue()
        } catch { alert(error) }
    }
    @objc private func batchURLs() {
        let a = NSAlert(); a.messageText = "Batch URLs"; a.informativeText = "Enter one HTTP or HTTPS URL per line."; a.addButton(withTitle:"Add"); a.addButton(withTitle:"Cancel")
        let text = NSTextView(frame:NSRect(x:0,y:0,width:450,height:180));text.isRichText = false; let scroll = NSScrollView(frame:text.frame); scroll.documentView = text; scroll.hasVerticalScroller = true; a.accessoryView = scroll
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        addBatch(text.string.components(separatedBy:.newlines), directory:directory)
    }
    private func addBatch(_ lines:[String], directory:URL) {
        do {
            var additions = [DownloadJob]()
            for line in lines where !line.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                guard let url = URL(string:line.trimmingCharacters(in:.whitespacesAndNewlines)) else { throw DownloadError.invalidURL }
                let name = DownloadFilename.from(url)
                var destination = directory.appendingPathComponent(name); var suffix = 1
                while FileManager.default.fileExists(atPath:destination.path) || (jobs + additions).contains(where:{$0.destination == destination}) {
                    destination = directory.appendingPathComponent("\(suffix)-\(name)"); suffix += 1
                }
                additions.append(try DownloadJob(url:url,destination:destination))
            }
            jobs += additions; persist(); refresh(); pumpQueue()
        } catch { alert(error) }
    }
    @objc private func resume() { if let job = selected { resumeJob(job.id) } }
    private func resumeJob(_ id:UUID) {
        guard let job = jobs.first(where:{$0.id == id}), let index = jobs.firstIndex(where:{$0.id == job.id}), job.state != .completed, tasks[job.id] == nil else { return }
        guard job.browserSourceURL == nil else { alert(DownloadError.browserLocalURL); return }
        jobs[index].state = .queued; jobs[index].error = nil; jobs[index].scheduledAt = nil
        runningQueue = true; persist(); pumpQueue(); refresh()
    }
    @objc private func stop() { if let job = selected { pause(job.id) }; refresh() }
    private func pause(_ id:UUID) {
        browserIntegration?.abort(jobID:id)
        tasks[id]?.cancel()
        if let i = jobs.firstIndex(where:{$0.id == id}), jobs[i].state == .queued || jobs[i].state == .downloading { jobs[i].state = .paused }
        persist()
    }
    func prepareForTermination() {
        runningQueue = false
        browserIntegration?.stop()
        for task in tasks.values { task.cancel() }
        for index in jobs.indices where jobs[index].state == .downloading { jobs[index].state = .paused }
        persist()
    }
    @objc func stopAll() { runningQueue = false; for id in jobs.map(\.id) { pause(id) }; refresh() }
    @objc private func startQueue() { runningQueue = true; pumpQueue(); refresh() }
    @objc private func stopQueue() { runningQueue = false; refresh() }
    private func pumpQueue() {
        guard runningQueue, tasks.isEmpty, let job = QueuePolicy.next(in:jobs) else { return }
        guard let index = jobs.firstIndex(where:{$0.id == job.id}) else { return }
        jobs[index].state = .downloading; jobs[index].error = nil
        guard persist() else { jobs[index].state = .paused; return }; refresh()
        let engine = self.engine; let options = self.options
        tasks[job.id] = Task { [weak self] in
            do {
                let authorization = try CredentialStore.authorization(jobID:job.id)
                try await engine.run(job:job,options:options,authorization:authorization,headers:CredentialStore.headers(jobID:job.id)) { [weak self] update in
                    await self?.update(job.id, update)
                }
                self?.finished(job.id,error:nil)
            } catch { self?.finished(job.id,error:error) }
        }
    }
    private func update(_ id:UUID,_ progress:TransferProgress) {
        guard let i = jobs.firstIndex(where:{$0.id == id}), jobs[i].state == .downloading else { return }
        let now = Date()
        if let previous = progressTimes[id] { let elapsed = now.timeIntervalSince(previous.0); progressTimes[id] = (now,progress.received,elapsed > 0 ? Double(max(0,progress.received-previous.1))/elapsed : previous.2) }
        else { progressTimes[id] = (now,progress.received,0) }
        jobs[i].receivedBytes = progress.received; jobs[i].totalBytes = progress.total
        if now.timeIntervalSince(lastPersist) > 1 { persist() }; refresh()
    }
    private func finished(_ id:UUID,error:Error?) {
        tasks.removeValue(forKey:id)
        guard let i = jobs.firstIndex(where:{$0.id == id}) else { return }
        if error == nil { jobs[i].state = .completed }
        else if error is CancellationError { jobs[i].state = .paused }
        else { jobs[i].state = .failed; jobs[i].error = error?.localizedDescription }
        persist(); refresh(); pumpQueue()
    }
    @objc private func deleteJob() {
        guard let job = selected else { return }
        if tasks[job.id] != nil { pause(job.id); status.stringValue = "Stopping download; delete it after it pauses."; return }
        let a = NSAlert(); a.messageText = "Remove \(job.destination.lastPathComponent)?"; a.informativeText = "Removes the job and partial data. Completed files remain in their destination."; a.addButton(withTitle:"Remove"); a.addButton(withTitle:"Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { try engine.discard(jobID:job.id); try CredentialStore.delete(jobID:job.id); try CredentialStore.deleteHeaders(jobID:job.id); browserIntegration?.abort(jobID:job.id); jobs.removeAll(where:{$0.id == job.id}); persist(); refresh() } catch { alert(error) }
    }
    @objc private func showProgress() {
        guard let job = selected else { return }
        detailsController = DownloadDetailsController(job:job,onResume:{ [weak self] in self?.resumeJob(job.id) },onPause:{ [weak self] in self?.pause(job.id);self?.refresh() })
        detailsController?.showWindow(nil)
    }
    @objc private func schedule() {
        guard let job = selected, job.browserSourceURL == nil, job.state != .completed, tasks[job.id] == nil else { return }
        let a = NSAlert(); a.messageText = "Schedule Download"; a.addButton(withTitle:"Schedule"); a.addButton(withTitle:"Cancel")
        let picker = NSDatePicker(); picker.datePickerElements = [.yearMonthDay,.hourMinute]; picker.datePickerStyle = .textFieldAndStepper; picker.dateValue = Date().addingTimeInterval(60);picker.sizeToFit();a.accessoryView = picker
        guard a.runModal() == .alertFirstButtonReturn, let i = jobs.firstIndex(where:{$0.id == job.id}) else { return }
        jobs[i].scheduledAt = picker.dateValue; jobs[i].state = .queued; runningQueue = true; persist(); refresh()
    }
    @objc private func showOptions() {
        let a = NSAlert(); a.messageText = "Download Options"; a.informativeText = "Changes apply to the next download. The queue runs one file at a time."; a.addButton(withTitle:"Save"); a.addButton(withTitle:"Cancel")
        let connections = textField("Connections (1–16)"); connections.stringValue = String(options.connections)
        let speed = textField("Speed limit in KiB/s (0 = unlimited)"); speed.stringValue = String(options.bytesPerSecond/1024)
        let host = textField("HTTP proxy host (optional)"); host.stringValue = options.proxyHost ?? ""
        let port = textField("Proxy port"); port.stringValue = String(options.proxyPort ?? 8080)
        let stack = NSStackView(views:[NSTextField(labelWithString:"Connections"),connections,NSTextField(labelWithString:"Speed limit (KiB/s)"),speed,NSTextField(labelWithString:"Proxy"),host,port]); stack.orientation = .vertical; stack.alignment = .leading;stack.spacing = 8;stack.frame.size = stack.fittingSize;a.accessoryView = stack
        guard a.runModal() == .alertFirstButtonReturn else { return }
        guard let count = Int(connections.stringValue), (1...16).contains(count), let rate = Int64(speed.stringValue), (0...1_000_000).contains(rate), let proxyPort = Int(port.stringValue), (1...65535).contains(proxyPort) else { alert(DownloadError.storage("Invalid option values")); return }
        options.connections = count; options.bytesPerSecond = rate*1024; options.proxyHost = host.stringValue.isEmpty ? nil : host.stringValue; options.proxyPort = options.proxyHost == nil ? nil : proxyPort
        do { UserDefaults.standard.set(try JSONEncoder().encode(options),forKey:"downloadOptions") } catch { alert(error) }
    }
    @objc private func grabber() {
        let a = NSAlert(); a.messageText = "Site Grabber"; a.informativeText = "Find downloadable links on one public page. Review the links before adding them."; a.addButton(withTitle:"Find Links"); a.addButton(withTitle:"Cancel")
        let field = textField("https://example.com/page"); a.accessoryView = field
        guard a.runModal() == .alertFirstButtonReturn, let url = URL(string:field.stringValue), ["http","https"].contains(url.scheme ?? ""), url.host != nil else { return }
        Task { [weak self] in
            do {
                let links = try await SiteGrabber.links(on:url)
                self?.reviewLinks(links)
            } catch { self?.alert(error) }
        }
    }
    private func reviewLinks(_ links:[URL]) {
        let a = NSAlert(); a.messageText = "Found \(links.count) file links"; a.informativeText = "Remove any URLs you do not want to download."; a.addButton(withTitle:"Add Downloads"); a.addButton(withTitle:"Cancel")
        let text = NSTextView(frame:NSRect(x:0,y:0,width:520,height:250));text.isRichText = false; text.string = links.map(\.absoluteString).joined(separator:"\n"); let scroll = NSScrollView(frame:text.frame); scroll.documentView = text; scroll.hasVerticalScroller = true; a.accessoryView = scroll
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let directory = panel.url else { return }; addBatch(text.string.components(separatedBy:.newlines),directory:directory)
    }
}
