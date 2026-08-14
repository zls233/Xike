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
        if minutes == 0 { return XikeText.format("剩余 %lld 秒", seconds) }
        if seconds == 0 { return XikeText.format("剩余 %lld 分钟", minutes) }
        return XikeText.format("剩余 %lld 分 %lld 秒", minutes, seconds)
    }

    static func focusDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let totalMinutes = totalSeconds / 60
        guard totalMinutes > 0 else {
            return totalSeconds > 0 ? "不足 1 分钟".xikeLocalized : "0 分钟".xikeLocalized
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return XikeText.format("%lld 分钟", totalMinutes) }
        if minutes == 0 { return XikeText.format("%lld 小时", hours) }
        return XikeText.format("%lld 小时 %lld 分", hours, minutes)
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
