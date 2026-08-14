import SwiftUI

struct TasksView: View {
    @Bindable var store: AppStore
    @State private var selection: UUID?
    @State private var search = ""
    @State private var status: TaskStatusFilter = .active
    @State private var selectedTag: String?
    @State private var editingTask: TaskItem?
    @State private var showingEditor = false

    private var visibleTasks: [TaskItem] {
        store.tasks.filtered(search: search, status: status, tag: selectedTag)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(visibleTasks) { task in
                    HStack(spacing: 10) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isCompleted ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).lineLimit(1)
                            Text(task.tag ?? "无标签")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(task.id)
                    .contextMenu { taskMenu(task) }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, prompt: "搜索任务或标签")
            .toolbar {
                ToolbarItem {
                    Button("新建任务", systemImage: "plus") {
                        editingTask = nil
                        showingEditor = true
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                }
            }
        } detail: {
            if let task = store.tasks.task(id: selection) {
                taskDetail(task)
            } else {
                ContentUnavailableView("选择一个任务", systemImage: "checklist", description: Text("查看任务信息与累计专注记录。"))
            }
        }
        .navigationTitle("任务")
        .safeAreaInset(edge: .top) {
            HStack {
                Picker("状态", selection: $status) {
                    ForEach(TaskStatusFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("标签", selection: $selectedTag) {
                    Text("全部标签").tag(String?.none)
                    ForEach(store.tasks.tags, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .frame(width: 180)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(.bar)
        }
        .sheet(isPresented: $showingEditor) {
            TaskEditorView(task: editingTask) { title, tag, minutes in
                if var task = editingTask {
                    task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    task.tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
                    task.estimatedMinutes = minutes
                    store.tasks.update(task)
                } else if let created = store.tasks.create(title: title, tag: tag, estimatedMinutes: minutes) {
                    selection = created.id
                }
            }
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private func taskDetail(_ task: TaskItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title).font(.largeTitle.weight(.semibold))
                        Text(task.tag ?? "无标签").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(task.isCompleted ? "重新打开" : "标记完成") {
                        store.tasks.setCompleted(task.id, completed: !task.isCompleted)
                    }
                    Button("编辑") {
                        editingTask = task
                        showingEditor = true
                    }
                }
                HStack(spacing: 28) {
                    metric("预计", task.estimatedMinutes.map { XikeText.format("%lld 分钟", $0) } ?? "未设置".xikeLocalized)
                    metric("累计专注", XikeText.format("%lld 分钟", store.history.activeMinutes(for: task.id)))
                    metric("专注记录", XikeText.format("%lld 轮", store.history.records(for: task.id).count))
                }
                Divider()
                Button("为此任务开始专注", systemImage: "play.fill") {
                    store.selectedTaskID = task.id
                    _ = store.startSession(taskID: task.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.engine.canStart || task.isCompleted || task.isArchived)

                Text("专注记录").font(.headline)
                ForEach(store.history.records(for: task.id)) { record in
                    HStack {
                        Label(record.outcome == .completed ? "已完成" : "已中止", systemImage: record.outcome == .completed ? "checkmark.circle" : "xmark.circle")
                        Spacer()
                        Text(record.startedAt, format: .dateTime.year().month().day().hour().minute())
                        Text("\(Int((record.activeFocusDuration / 60).rounded())) 分钟")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title3.weight(.semibold))
            Text(title.xikeLocalized).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func taskMenu(_ task: TaskItem) -> some View {
        Button(task.isCompleted ? "重新打开" : "标记完成") { store.tasks.setCompleted(task.id, completed: !task.isCompleted) }
        Button(task.isArchived ? "取消归档" : "归档") { store.tasks.setArchived(task.id, archived: !task.isArchived) }
        Divider()
        Button("删除", role: .destructive) { store.tasks.delete(task.id) }
    }
}
