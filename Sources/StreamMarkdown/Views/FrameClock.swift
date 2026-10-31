#if canImport(UIKit)
import QuartzCore
import UIKit

/// Drives a stream from a display link while it has text to release or a parse to publish, so updates land at the
/// start of a frame. It asks for up to 120 Hz, which a ProMotion iPhone grants with `CADisableMinimumFrameDurationOnPhone`.
@MainActor
final class DisplayLinkClock: FrameClock {
    weak var stream: MarkdownStream?
    private var link: CADisplayLink?

    func requestFrames() {
        if link == nil {
            let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in self?.tick($0) }, selector: #selector(DisplayLinkTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        link?.isPaused = false
    }

    private func tick(_ link: CADisplayLink) {
        guard let stream else { return link.invalidate() }
        if !stream.frame(at: link.timestamp) { link.isPaused = true }
    }

    isolated deinit {
        link?.invalidate()
    }
}

/// A display link's target that holds its owner weakly, since a display link keeps its target alive.
final class DisplayLinkTarget: NSObject {
    private let action: (CADisplayLink) -> Void

    init(_ action: @escaping (CADisplayLink) -> Void) {
        self.action = action
    }

    @objc func tick(_ link: CADisplayLink) { action(link) }
}
#endif
