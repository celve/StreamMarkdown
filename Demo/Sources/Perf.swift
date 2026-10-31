import Foundation
import QuartzCore
import SwiftUI

/// The probe from LIN-2404's renderer comparison (softlash/LIN-2404 docs/compare/Host/Perf.swift), so runs compare: frames
/// and hitches from a display link, main-thread busy time from a run-loop observer, and the app's memory footprint.
@MainActor
final class Perf: ObservableObject {
    static let shared = Perf()

    var frames = 0, hitches = 0, hitchMs = 0.0, worstMs = 0.0, busyMs = 0.0
    /// Main-thread stretches between run-loop waits: the longest, and how many overran a 120 Hz and a 60 Hz frame.
    var longestBusyMs = 0.0, busyOver8 = 0, busyOver16 = 0
    private var last: CFTimeInterval = 0
    private var link: CADisplayLink?
    private var wokeAt: CFAbsoluteTime = 0
    /// Where a scroll is, 0 at the top and 1 at the bottom, for the run to follow.
    @Published var scrollProgress: Double = 0

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: Target { [weak self] link in self?.tick(link) }, selector: #selector(Target.tick(_:)))
        // Asks for the display's top rate, which an iPhone grants above 60 Hz only with CADisableMinimumFrameDurationOnPhone.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, activity in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = CFAbsoluteTimeGetCurrent()
                if activity == .afterWaiting { self.wokeAt = now } else if self.wokeAt > 0 { self.busy((now - self.wokeAt) * 1000); self.wokeAt = 0 }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last > 0 else { return }
        frames += 1
        let gap = (link.timestamp - last) * 1000, expected = (link.targetTimestamp - link.timestamp) * 1000
        worstMs = max(worstMs, gap)
        if gap > max(expected, 8.3) * 1.5 { hitches += 1; hitchMs += gap - max(expected, 8.3) }
    }

    private func busy(_ ms: Double) {
        busyMs += ms
        longestBusyMs = max(longestBusyMs, ms)
        if ms > 8.3 { busyOver8 += 1 }
        if ms > 16.7 { busyOver16 += 1 }
    }

    func reset() { frames = 0; hitches = 0; hitchMs = 0; worstMs = 0; busyMs = 0; longestBusyMs = 0; busyOver8 = 0; busyOver16 = 0 }

    func line(_ label: String, seconds: Double) -> String {
        String(format: "%@ frames=%d fps=%.0f hitches=%d hitchMsPerS=%.0f worstMs=%.0f busyMsPerS=%.0f longestBusyMs=%.1f busyOver8ms=%d busyOver16ms=%d", label, frames, Double(frames) / seconds, hitches, hitchMs / seconds, worstMs, busyMs / seconds, longestBusyMs, busyOver8, busyOver16)
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    static func log(_ s: String) {
        print("PERF " + s)
        fflush(stdout)
    }

    private final class Target: NSObject {
        let action: (CADisplayLink) -> Void
        init(_ action: @escaping (CADisplayLink) -> Void) { self.action = action }
        @objc func tick(_ link: CADisplayLink) { action(link) }
    }
}
