import AppKit
import IDMCore

/// Light surfaces and colored controls inspired by the original IDM window.
@MainActor enum IDMTheme {
    static let sidebar = NSColor(srgbRed:0.956,green:0.96,blue:0.964,alpha:1)
    static func stateColor(_ state:JobState) -> NSColor {
        switch state { case .completed:green; case .failed:.systemRed; case .downloading:blue; case .paused:.secondaryLabelColor; case .queued:.secondaryLabelColor }
    }
    static let blue = NSColor(srgbRed:0.12,green:0.43,blue:0.76,alpha:1)
    static let green = NSColor(srgbRed:0.16,green:0.57,blue:0.36,alpha:1)
    static let orange = NSColor(srgbRed:0.83,green:0.43,blue:0.14,alpha:1)
    static let purple = NSColor(srgbRed:0.48,green:0.36,blue:0.71,alpha:1)
    static func color(_ action:String) -> NSColor {
        switch action {
        case "add","resume","startQueue","Finished":green
        case "stop","stopAll","stopQueue","Unfinished":orange
        case "delete":.systemRed
        case "options","schedule","Music","Video":purple
        default:blue
        }
    }
    static func icon(_ symbol:String, color:NSColor, size:CGFloat = 28) -> NSImage? {
        guard let image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:size,weight:.regular)) else { return nil }
        let rendered = NSImage(size:image.size)
        rendered.lockFocus()
        image.draw(at:.zero,from:.zero,operation:.sourceOver,fraction:1)
        color.setFill();NSRect(origin:.zero,size:image.size).fill(using:.sourceAtop)
        rendered.unlockFocus();rendered.isTemplate = false
        return rendered
    }
    static func categorySymbol(_ name:String) -> String {
        switch name {
        case "All Downloads":"folder.fill"
        case "Compressed":"archivebox.fill"
        case "Documents":"doc.text.fill"
        case "Music":"music.note"
        case "Programs":"app.fill"
        case "Video":"film.fill"
        case "Unfinished":"arrow.down.circle.fill"
        case "Finished":"checkmark.circle.fill"
        case "Grabber projects":"globe"
        case "Queues","Main Queue":"tray.2.fill"
        default:"doc.fill"
        }
    }
}
