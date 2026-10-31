import Foundation

// TEMPORARY: switches for attributing perf cost; removed before review.
enum Tuning {
    static let env = ProcessInfo.processInfo.environment
    static let wordFade = env["SM_FADE"] != "0"
    static let blockFade = env["SM_BLOCKFADE"] != "0"
    static let pace = env["SM_PACE"] != "0"
    static let tailReplace = env["SM_TAIL"] != "0"
    static let slots = env["SM_SLOTS"] != "0"
    static let repair = env["SM_REPAIR"] != "0"
}
