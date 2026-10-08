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
        let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:580,height:330),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        panel.appearance = NSAppearance(named:.aqua);panel.title = "Download Details";panel.center()
        super.init(window:panel)
        guard let content = panel.contentView else { return }
        let name = NSTextField(labelWithString:job.destination.lastPathComponent);name.font = .systemFont(ofSize:16,weight:.semibold);name.lineBreakMode = .byTruncatingMiddle
        let source = NSTextField(wrappingLabelWithString:job.url.absoluteString);source.textColor = .secondaryLabelColor;source.maximumNumberOfLines = 2;source.lineBreakMode = .byTruncatingMiddle;source.toolTip = job.url.absoluteString
        let destination = NSTextField(wrappingLabelWithString:job.destination.path);destination.textColor = .secondaryLabelColor;destination.maximumNumberOfLines = 2;destination.lineBreakMode = .byTruncatingMiddle;destination.toolTip = job.destination.path
        progress.style = .bar;progress.minValue = 0;progress.maxValue = 1
        errorLabel.textColor = .systemRed;errorLabel.maximumNumberOfLines = 4
        resumeButton.target = self;resumeButton.action = #selector(resume)
        pauseButton.target = self;pauseButton.action = #selector(pause)
        revealButton.target = self;revealButton.action = #selector(reveal)
        let open = NSButton(title:"Open Page",target:self,action:#selector(openPage));open.toolTip = "Open the source URL in your browser"
        let actions = NSStackView(views:[resumeButton,pauseButton,revealButton,open]);actions.spacing = 10;actions.distribution = .fillProportionally
        for button in [resumeButton,pauseButton,revealButton,open] { button.bezelStyle = .rounded;button.controlSize = .regular;button.heightAnchor.constraint(greaterThanOrEqualToConstant:28).isActive = true }
        let stack = NSStackView(views:[name,source,destination,stateLabel,progress,amountLabel,errorLabel,NSView(),actions]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing = 10;stack.translatesAutoresizingMaskIntoConstraints = false;content.addSubview(stack)
        for view in [name,source,destination,progress,amountLabel,errorLabel,actions] { view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-20),stack.topAnchor.constraint(equalTo:content.topAnchor,constant:20),stack.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-20)])
        update(job,speed:0)
    }
    required init?(coder:NSCoder) { fatalError("Not supported") }
    func update(_ job:DownloadJob,speed:Double) {
        self.job = job;stateLabel.stringValue = job.state.rawValue.capitalized
        amountLabel.stringValue = ByteCountFormatter.string(fromByteCount:job.receivedBytes,countStyle:.file) + " of " + (job.totalBytes >= 0 ? ByteCountFormatter.string(fromByteCount:job.totalBytes,countStyle:.file) : "unknown size") + " · " + ByteCountFormatter.string(fromByteCount:Int64(speed),countStyle:.file) + "/s"
        progress.isIndeterminate = job.totalBytes <= 0 && job.state == .downloading
        progress.doubleValue = job.state == .completed ? 1 : job.totalBytes > 0 ? min(1,Double(job.receivedBytes)/Double(job.totalBytes)) : 0
        if progress.isIndeterminate { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        errorLabel.stringValue = job.error ?? "";errorLabel.isHidden = job.error == nil
        resumeButton.isEnabled = job.state == .paused || job.state == .failed
        pauseButton.isEnabled = job.state == .downloading || job.state == .queued
        revealButton.isEnabled = job.state == .completed
    }
    @objc private func resume() { onResume() }
    @objc private func pause() { onPause() }
    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([job.destination]) }
    @objc private func openPage() { NSWorkspace.shared.open(job.url) }
}
