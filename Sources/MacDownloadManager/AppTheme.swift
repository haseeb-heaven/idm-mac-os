import AppKit
import DownloadCore

enum ToolbarAppearance:String { case classic, compact }
enum InterfaceAppearance:String {
    case light, dark, system
    var appKit:NSAppearance? { switch self { case .light:NSAppearance(named:.aqua); case .dark:NSAppearance(named:.darkAqua); case .system:nil } }
}

/// Light surfaces and colored controls for the classic toolbar theme.
@MainActor enum AppTheme {
    static let sidebar = NSColor(name:"MacDownloadManager.sidebar") { appearance in
        appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? NSColor(white:0.14,alpha:1) : NSColor(srgbRed:0.956,green:0.96,blue:0.964,alpha:1)
    }
    static func stateColor(_ state:JobState) -> NSColor {
        switch state { case .completed:green; case .failed:.systemRed; case .downloading:blue; case .paused:.secondaryLabelColor; case .queued:.secondaryLabelColor }
    }
    static let blue = NSColor(srgbRed:0.12,green:0.43,blue:0.76,alpha:1)
    static let green = NSColor(srgbRed:0.16,green:0.57,blue:0.36,alpha:1)
    static let orange = NSColor(srgbRed:0.83,green:0.43,blue:0.14,alpha:1)
    static let purple = NSColor(srgbRed:0.48,green:0.36,blue:0.71,alpha:1)
    static func color(_ action:String) -> NSColor {
        switch action {
        case "All Downloads","Compressed","Queues","Main Queue":NSColor(srgbRed:0.77,green:0.59,blue:0.06,alpha:1)
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
    /// Independently drawn classic toolbar metaphors, with no copied MacDownloadManager bitmaps.
    static func classicIcon(_ action:String) -> NSImage? {
        let symbols:[String:String] = ["resume":"play.circle.fill","stop":"pause.circle.fill","stopAll":"pause.rectangle.fill","delete":"trash.fill","details":"info.circle.fill","options":"gearshape.fill","schedule":"alarm.fill","startQueue":"tray.and.arrow.down.fill","stopQueue":"tray.fill","grabber":"globe"]
        if action != "add" { return icon(symbols[action] ?? "doc.fill",color:color(action),size:26) }
        let image = NSImage(size:NSSize(width:32,height:32)); image.lockFocus()
        func sheet(_ y:CGFloat,_ color:NSColor) {
            let path = NSBezierPath(); path.move(to:NSPoint(x:3,y:y)); path.line(to:NSPoint(x:19,y:y-5)); path.line(to:NSPoint(x:29,y:y+4)); path.line(to:NSPoint(x:13,y:y+10)); path.close()
            color.setFill(); path.fill(); NSColor(srgbRed:0.61,green:0.47,blue:0.08,alpha:1).setStroke();path.lineWidth = 0.7;path.stroke()
        }
        sheet(8,NSColor(srgbRed:0.77,green:0.58,blue:0.06,alpha:1)); sheet(12,NSColor(srgbRed:0.99,green:0.83,blue:0.12,alpha:1)); sheet(16,NSColor(srgbRed:1,green:0.93,blue:0.28,alpha:1))
        NSColor.systemGreen.setFill(); NSBezierPath(ovalIn:NSRect(x:22,y:1,width:10,height:10)).fill()
        NSColor.white.setStroke(); let plus = NSBezierPath();plus.lineWidth = 1.4;plus.move(to:NSPoint(x:27,y:3));plus.line(to:NSPoint(x:27,y:9));plus.move(to:NSPoint(x:24,y:6));plus.line(to:NSPoint(x:30,y:6));plus.stroke()
        image.unlockFocus(); image.isTemplate = false;return image
    }
}
