import AppKit

/// Where the camera housing is, measured from the screen's real safe-area and auxiliary menu-bar areas.
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    /// The camera housing in global screen coordinates.
    let notchRect: CGRect

    var notchWidth: CGFloat { self.notchRect.width }
    var notchHeight: CGFloat { self.notchRect.height }

    static func detect(on screen: NSScreen) -> NotchGeometry? {
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }
        let frame = screen.frame
        let width = frame.width - left.width - right.width
        guard width > 40 else { return nil }
        let rect = CGRect(x: frame.minX + left.width, y: frame.maxY - topInset, width: width, height: topInset)
        return NotchGeometry(screenFrame: frame, notchRect: rect)
    }

    /// The first screen with a camera housing, if any.
    static func notchedScreen() -> (NSScreen, NotchGeometry)? {
        for screen in NSScreen.screens {
            if let geometry = self.detect(on: screen) { return (screen, geometry) }
        }
        return nil
    }
}
