import AppKit
import IDMCore

@MainActor final class DownloadDetailsController: NSWindowController {
    let jobID: UUID
    private var job: DownloadJob
    private let stateLabel = NSTextField(labelWithString: "")
    private let amountLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let resumeButton = NSButton(title: "Resume", target: nil, action: nil)
    private let pauseButton = NSButton(title: "Pause", target: nil, action: nil)
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private let onResume: () -> Void
    private let onPause: () -> Void
    init(job:DownloadJob,onResume:@escaping () -> Void,onPause:@escaping () -> Void) {
        self.job = job;jobID = job.id;self.onResume = onResume;self.onPause = onPause
        let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:620,height:340),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        panel.appearance = NSAppearance(named:.aqua);panel.title = "Download Details";panel.center()
        super.init(window:panel)
        guard let content = panel.contentView else { return }
        let name = NSTextField(labelWithString:job.destination.lastPathComponent); name.font = .systemFont(ofSize:15,weight:.semibold); name.lineBreakMode = .byTruncatingMiddle; name.toolTip = job.destination.lastPathComponent
        stateLabel.font = .systemFont(ofSize:11,weight:.medium)
        let title = NSStackView(views:[name,stateLabel]); title.orientation = .vertical; title.alignment = .leading; title.spacing = 5
        let icon = NSImageView(image:NSWorkspace.shared.icon(forFile:job.destination.path)); icon.widthAnchor.constraint(equalToConstant:32).isActive = true; icon.heightAnchor.constraint(equalToConstant:32).isActive = true
        let header = NSStackView(views:[icon,title]); header.spacing = 12; header.alignment = .centerY
        let source = NSTextField(wrappingLabelWithString:job.url.absoluteString); source.font = .systemFont(ofSize:11); source.textColor = .secondaryLabelColor; source.maximumNumberOfLines = 2; source.lineBreakMode = .byTruncatingMiddle; source.toolTip = job.url.absoluteString; source.isSelectable = true
        let destination = NSTextField(wrappingLabelWithString:job.destination.path); destination.font = .systemFont(ofSize:11); destination.textColor = .secondaryLabelColor; destination.maximumNumberOfLines = 2; destination.lineBreakMode = .byTruncatingMiddle; destination.toolTip = job.destination.path; destination.isSelectable = true
        func fieldRow(_ caption:String,_ field:NSTextField) -> NSStackView {
            let label = NSTextField(labelWithString:caption); label.font = .systemFont(ofSize:11,weight:.medium); label.textColor = .secondaryLabelColor; label.widthAnchor.constraint(equalToConstant:72).isActive = true
            let row = NSStackView(views:[label,field]); row.alignment = .firstBaseline; row.spacing = 12
            field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal); return row
        }
        let sourceRow = fieldRow("Source",source), destinationRow = fieldRow("Save to",destination)
        let separator = NSBox(); separator.boxType = .separator
        progress.style = .bar; progress.controlSize = .small; progress.minValue = 0; progress.maxValue = 1
        amountLabel.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); amountLabel.textColor = .secondaryLabelColor
        errorLabel.font = .systemFont(ofSize:12); errorLabel.textColor = .systemRed; errorLabel.maximumNumberOfLines = 3
        resumeButton.target = self; resumeButton.action = #selector(resume)
        pauseButton.target = self; pauseButton.action = #selector(pause)
        revealButton.target = self; revealButton.action = #selector(reveal)
        let open = NSButton(title:"Open Website",target:self,action:#selector(openPage)); open.toolTip = "Open the source URL in your browser"
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let actions = NSStackView(views:[resumeButton,pauseButton,spacer,open,revealButton]); actions.spacing = 8
        for button in [resumeButton,pauseButton,revealButton,open] { button.bezelStyle = .rounded; button.controlSize = .small; button.font = .systemFont(ofSize:12); button.heightAnchor.constraint(greaterThanOrEqualToConstant:26).isActive = true }
        let stack = NSStackView(views:[header,separator,sourceRow,destinationRow,progress,amountLabel,errorLabel,NSView(),actions]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        for view in [header,separator,sourceRow,destinationRow,progress,amountLabel,errorLabel,actions] { view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true }
        name.widthAnchor.constraint(equalTo:title.widthAnchor).isActive = true
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:22),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-22),stack.topAnchor.constraint(equalTo:content.topAnchor,constant:22),stack.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-20)])
        update(job,speed:0)
    }
    required init?(coder:NSCoder) { fatalError("Not supported") }
    func update(_ job:DownloadJob,speed:Double) {
        self.job = job; stateLabel.stringValue = job.state.rawValue.capitalized; stateLabel.textColor = IDMTheme.stateColor(job.state)
        amountLabel.stringValue = ByteCountFormatter.string(fromByteCount:job.receivedBytes,countStyle:.file) + " of " + (job.totalBytes >= 0 ? ByteCountFormatter.string(fromByteCount:job.totalBytes,countStyle:.file) : "unknown size") + " · " + ByteCountFormatter.string(fromByteCount:Int64(speed),countStyle:.file) + "/s"
        progress.isIndeterminate = job.totalBytes <= 0 && job.state == .downloading
        progress.doubleValue = job.state == .completed ? 1 : job.totalBytes > 0 ? min(1,Double(job.receivedBytes)/Double(job.totalBytes)) : 0
        if progress.isIndeterminate { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        errorLabel.stringValue = job.error ?? "";errorLabel.isHidden = job.error == nil
        resumeButton.isEnabled = job.browserSourceURL == nil && (job.state == .paused || job.state == .failed)
        pauseButton.isEnabled = job.state == .downloading || job.state == .queued
        revealButton.isEnabled = job.state == .completed
    }
    @objc private func resume() { onResume() }
    @objc private func pause() { onPause() }
    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([job.destination]) }
    @objc private func openPage() { NSWorkspace.shared.open(job.url) }
}
