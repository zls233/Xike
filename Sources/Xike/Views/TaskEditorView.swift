import SwiftUI

struct TaskEditorView: View {
    let task: TaskItem?
    let onSave: (String, String?, Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var tag: String
    @State private var estimatedMinutes: Int
    @State private var hasEstimate: Bool

    init(task: TaskItem? = nil, onSave: @escaping (String, String?, Int?) -> Void) {
        self.task = task
        self.onSave = onSave
        _title = State(initialValue: task?.title ?? "")
        _tag = State(initialValue: task?.tag ?? "")
        _estimatedMinutes = State(initialValue: task?.estimatedMinutes ?? 45)
        _hasEstimate = State(initialValue: task?.estimatedMinutes != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(task == nil ? "新建任务" : "编辑任务")
                .font(.title2.weight(.semibold))
            Form {
                TextField("任务标题", text: $title)
                TextField("标签（可选）", text: $tag)
                Toggle("设置预计时长", isOn: $hasEstimate)
                if hasEstimate {
                    Stepper("预计 \(estimatedMinutes) 分钟", value: $estimatedMinutes, in: 5 ... 480, step: 5)
                }
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(title, tag, hasEstimate ? estimatedMinutes : nil)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
