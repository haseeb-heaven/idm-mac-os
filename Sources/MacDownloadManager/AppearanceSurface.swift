import AppKit

/// Resolve layer colors again when macOS changes system appearance.
@MainActor final class AppearanceSurface:NSStackView {
    var surfaceColor:NSColor = .textBackgroundColor {
        didSet { updateSurfaceColor() }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance();updateSurfaceColor()
    }
    private func updateSurfaceColor() {
        wantsLayer = true
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = surfaceColor.cgColor }
    }
}
