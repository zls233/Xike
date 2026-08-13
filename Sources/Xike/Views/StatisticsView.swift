import Charts
import SwiftUI

struct StatisticsView: View {
    @Bindable var store: AppStore

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var today: TodayStatistics { store.history.statistics(for: store.statisticsDate) }
    private var week: [DailyFocusSummary] { store.history.summaries(endingAt: store.statisticsDate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("今天")
                .font(.headline)

            HStack(spacing: 10) {
                stat(value: "\(today.completedCycles)", label: "完成轮数")
                stat(value: "\(today.activeMinutes)", label: "专注分钟")
                stat(
                    value: today.microBreakCompletionRate.formatted(.percent.precision(.fractionLength(0))),
                    label: "微休息完成"
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("近 7 天")
                    .font(.subheadline.weight(.semibold))
                Chart(week) { item in
                    BarMark(
                        x: .value("日期", item.date, unit: .day),
                        y: .value("分钟", item.minutes)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 154)
                .accessibilityLabel("近七天专注时长图表")
            }

            if let latest = store.history.records.first {
                Divider()
                HStack {
                    Label("最近一轮", systemImage: latest.outcome == .completed ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(latest.startedAt, format: .dateTime.month().day().hour().minute())
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
        }
        .padding(24)
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
