import Foundation

struct AlertPolicy {
    static let repeatInterval: TimeInterval = 5 * 60
    private var lastWarning: Date?
    var warned: Bool { lastWarning != nil }

    mutating func evaluate(percent: Int, onPower: Bool, threshold: Int, now: Date = Date()) -> Bool {
        if onPower || percent > threshold { lastWarning = nil; return false }
        guard lastWarning.map({ now.timeIntervalSince($0) >= Self.repeatInterval }) ?? true else { return false }
        lastWarning = now
        return true
    }
    mutating func retry() { lastWarning = nil }
}
