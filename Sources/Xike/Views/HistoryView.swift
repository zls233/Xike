import SwiftUI

struct HistoryView: View {
    @Bindable var store: AppStore
    @State private var search = ""

    private var records: [SessionRecordValue] {
        guard !search.isEmpty else { return store.history.records }
        return store.history.records.filter {
            ($0.focusContext?.taskTitleSnapshot?.localizedCaseInsensitiveContains(search) ?? false)
                || ($0.focusContext?.goal?.localizedCaseInsensitiveContains(search) ?? false)
                || ($0.focusContext?.reflection?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        List(records) { record in
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(record.focusContext?.taskTitleSnapshot ?? record.focusContext?.goal ?? "未命名专注", systemImage: record.outcome == .completed ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.headline)
                    Spacer()
                    Text(record.startedAt, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    Text("专注 \(Int((record.activeFocusDuration / 60).rounded())) 分钟")
                    Text("微休息 \(record.microBreaksCompleted)/\(record.microBreaksTriggered)")
                    if let reflection = record.focusContext?.reflection { Text(reflection).lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
        }
        .searchable(text: $search, prompt: "搜索任务、目标或复盘")
        .navigationTitle("专注记录")
        .frame(minWidth: 680, minHeight: 480)
    }
}
