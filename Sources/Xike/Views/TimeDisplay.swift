import Foundation

enum TimeDisplay {
    static func clock(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(ceil(interval)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func accessibilityDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(ceil(interval)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 { return "剩余 \(seconds) 秒" }
        if seconds == 0 { return "剩余 \(minutes) 分钟" }
        return "剩余 \(minutes) 分 \(seconds) 秒"
    }
}

extension SessionPhase {
    var systemImage: String {
        switch self {
        case .idle: "circle.dotted"
        case .focusing: "scope"
        case .microBreak: "wind"
        case .longBreak: "cup.and.saucer"
        case .awaitingNextCycle: "checkmark.circle"
        }
    }
}
