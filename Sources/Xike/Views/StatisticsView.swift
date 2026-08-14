import Charts
import SwiftUI

struct StatisticsView: View {
    @Bindable var store: AppStore

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var today: TodayStatistics { store.todayStatistics }
    private var week: [DailyFocusSummary] { store.recentDailyFocusSummaries }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日专注")
                    .font(.headline)
                Spacer()
                if store.engine.phase.isRunning {
                    Text("包含当前轮")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(TimeDisplay.focusDuration(store.todayActiveFocusDuration))
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel(XikeText.format("今日专注 %@", TimeDisplay.focusDuration(store.todayActiveFocusDuration)))

            HStack(spacing: 10) {
                stat(value: "\(today.completedCycles)", label: "完成轮数".xikeLocalized)
                stat(
                    value: today.microBreakCompletionRate.formatted(.percent.precision(.fractionLength(0))),
                    label: "微休息完成".xikeLocalized
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("近 7 天")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Chart(week) { item in
                    BarMark(
                        x: .value("日期".xikeLocalized, item.date, unit: .day),
                        y: .value("分钟".xikeLocalized, item.minutes)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 68)
                .accessibilityLabel("近七天专注时长图表")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial))
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
