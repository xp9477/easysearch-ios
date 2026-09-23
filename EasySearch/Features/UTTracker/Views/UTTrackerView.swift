import SwiftUI
import UIKit
import SceneKit

public struct UTTrackerView: View {
    @StateObject private var viewModel = UTTrackerViewModel()
    @State private var selectedDate = Date()
    @State private var draftHours = UTTrackerMetrics.dailyReferenceHours
    @State private var draftNote = ""
    @State private var selectedFactory: String
    @State private var selectedMachine = ""
    @State private var newMachineName = ""
    @State private var showingMoreOptions = false
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showingRenameAlert = false
    @State private var factoryToRename = ""
    @State private var newFactoryName = ""

    public init() {
        let initialFactory = UserDefaults.standard.string(forKey: UTTrackerStorage.lastFactoryKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedFactories = UserDefaults.standard.stringArray(forKey: UTTrackerStorage.factoriesKey)?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        let effectiveFactories = (savedFactories.count == 2 && savedFactories[0] != savedFactories[1])
            ? savedFactories
            : UTFactoryLayout.defaultFactories

        let factory: String
        if let initialFactory, effectiveFactories.contains(initialFactory) {
            factory = initialFactory
        } else {
            factory = effectiveFactories[0]
        }
        _selectedFactory = State(initialValue: factory)
        _selectedMachine = State(initialValue: UserDefaults.standard.string(forKey: UTTrackerStorage.lastMachineKey) ?? "")
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                ESModuleHero(
                    title: "UT 记录",
                    subtitle: "工时追踪 · 70% 目标达成",
                    featureID: "uttracker",
                    systemImage: "chart.bar.doc.horizontal"
                )
                progressCard
                machineDurationCard
                quickLogCard
                if !viewModel.currentMonthEntries.isEmpty {
                    currentMonthEntriesCard
                }
                historyDisclosure
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.xxl)
        }
        .esScreenBackground()
        .onAppear {
            if selectedFactory.isEmpty || !viewModel.factories.contains(selectedFactory) {
                selectedFactory = viewModel.lastFactory
            }
            if selectedMachine.isEmpty && !viewModel.lastMachine.isEmpty {
                selectedMachine = viewModel.lastMachine
            }
        }
        .alert("重命名厂名", isPresented: $showingRenameAlert) {
            TextField("新厂名", text: $newFactoryName)
            Button("取消", role: .cancel) {
                factoryToRename = ""
                newFactoryName = ""
            }
            Button("确定") {
                let trimmed = newFactoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !factoryToRename.isEmpty {
                    let success = viewModel.renameFactory(factoryToRename, to: trimmed)
                    if success && selectedFactory == factoryToRename {
                        selectedFactory = trimmed
                    }
                }
                factoryToRename = ""
                newFactoryName = ""
            }
        } message: {
            Text("请输入「\(factoryToRename)」的新名称，不可为空且不能与另一厂重名。")
        }
        .navigationTitle("UT 记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("UT 设置")
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                UTTrackerSettingsDetailView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showingSettings = false }
                        }
                    }
            }
        }
    }

    // MARK: - Progress

    private var progressCard: some View {
        let summary = viewModel.currentMonthSummary
        let progress = clamped(summary.targetProgress)

        return VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack(alignment: .center, spacing: ESUI.Space.lg) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            summary.isTargetMet ? Color.green : Color.orange,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(ESMotion.value, value: progress)

                    VStack(spacing: 0) {
                        Text(percentText(for: summary.targetProgress))
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text("70% 目标")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 108, height: 108)

                VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                    Text(monthRangeText(for: summary))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("\(hoursText(summary.totalHours)) / \(hoursText(summary.targetHours))h")
                        .font(.title3.weight(.semibold).monospacedDigit())

                    if summary.isTargetMet {
                        ESStatusBadge(text: "已达标 · 超出 \(hoursText(max(0, summary.totalHours - summary.targetHours)))h", tone: .success)
                    } else {
                        ESStatusBadge(text: "还差 \(hoursText(summary.remainingToTarget))h", tone: .warning)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .esCard()
    }

    // MARK: - Machine Duration

    private var machineDurationCard: some View {
        let groups = viewModel.factoryHourGroups

        return VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: "机台时长",
                subtitle: "最近一年 · 两个厂"
            )

            UTFactoryHoursScene(groups: groups)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous))

            Text("拖动旋转")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                        HStack(spacing: ESUI.Space.xs) {
                            Circle()
                                .fill(group.factory == viewModel.factories.first ? Color.blue : Color.orange)
                                .frame(width: 8, height: 8)

                            Text(group.factory)
                                .font(.subheadline.weight(.semibold))

                            Button("重命名") {
                                factoryToRename = group.factory
                                newFactoryName = group.factory
                                showingRenameAlert = true
                            }
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .buttonStyle(.plain)

                            Spacer()

                            Text("\(hoursText(group.totalHours))h")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        if group.totals.isEmpty {
                            Text("暂无设备")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 12)
                        } else {
                            VStack(spacing: 4) {
                                ForEach(group.totals) { item in
                                    HStack {
                                        Text(item.machine)
                                            .font(.caption.weight(.medium))
                                        Spacer()
                                        Text("\(hoursText(item.totalHours))h")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, ESUI.Space.sm)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(ESUI.fill)
                                    )
                                }
                            }
                        }
                    }
                    .padding(ESUI.Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                            .fill(ESUI.fill.opacity(0.4))
                    )
                }
            }
        }
        .esCard()
    }

    // MARK: - Quick Log

    private var quickLogCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.md) {
            HStack {
                Text("快速记录")
                    .font(.headline)
                Spacer()
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

            VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                Text("厂区")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: ESUI.Space.xs) {
                    ForEach(viewModel.factories, id: \.self) { factory in
                        presetButton(
                            title: factory,
                            isSelected: selectedFactory == factory
                        ) {
                            selectedFactory = factory
                            viewModel.rememberFactory(factory)
                            if !selectedMachine.isEmpty, !viewModel.machines(in: factory).contains(selectedMachine) {
                                selectedMachine = ""
                                viewModel.rememberMachine("")
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                Text("机台")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 72), spacing: ESUI.Space.xs)],
                    alignment: .leading,
                    spacing: ESUI.Space.xs
                ) {
                    presetButton(
                        title: "不选",
                        isSelected: selectedMachine.isEmpty
                    ) {
                        selectedMachine = ""
                        viewModel.rememberMachine("")
                    }

                    ForEach(viewModel.machines(in: selectedFactory), id: \.self) { machine in
                        presetButton(
                            title: machine,
                            isSelected: selectedMachine == machine
                        ) {
                            selectedMachine = machine
                            viewModel.rememberMachine(machine)
                        }
                    }
                }

                HStack(spacing: ESUI.Space.xs) {
                    TextField("新机台名称", text: $newMachineName)
                        .font(.subheadline)
                        .padding(.horizontal, ESUI.Space.sm)
                        .padding(.vertical, ESUI.Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                .fill(ESUI.fill)
                        )
                        .onSubmit(addNewMachine)

                    Button(action: addNewMachine) {
                        Text("添加")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, ESUI.Space.md)
                            .padding(.vertical, ESUI.Space.xs)
                            .background(
                                RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                    .fill(newMachineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ESUI.fill : Color.accentColor.opacity(0.12))
                            )
                            .foregroundStyle(newMachineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(newMachineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: ESUI.Space.xs)],
                alignment: .leading,
                spacing: ESUI.Space.xs
            ) {
                ForEach(quickHourOptions, id: \.self) { hours in
                    presetButton(
                        title: "\(hoursText(hours))h",
                        isSelected: draftHours == hours
                    ) {
                        draftHours = hours
                    }
                }

                if let remainingSuggestion = remainingSuggestionHours {
                    presetButton(
                        title: "补齐 \(hoursText(remainingSuggestion))h",
                        isSelected: draftHours == remainingSuggestion
                    ) {
                        draftHours = remainingSuggestion
                    }
                }
            }

            ESPrimaryCTA(
                title: saveButtonTitle,
                systemImage: "plus.circle.fill",
                enabled: draftHours > 0,
                action: saveEntry
            )

            DisclosureGroup("更多选项", isExpanded: $showingMoreOptions) {
                VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                    Stepper(value: $draftHours, in: 0.5...16, step: 0.5) {
                        Text("微调:\(hoursText(draftHours))h")
                            .font(.subheadline)
                    }

                    TextField("备注(可选)", text: $draftNote, axis: .vertical)
                        .lineLimit(3, reservesSpace: false)
                        .padding(.horizontal, ESUI.Space.sm)
                        .padding(.vertical, ESUI.Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                                .fill(ESUI.fill)
                        )

                    projectedBanner
                }
                .padding(.top, ESUI.Space.xs)
            }
            .font(.subheadline)
            .tint(.secondary)
        }
        .esCard()
    }

    private var projectedBanner: some View {
        let summary = selectedMonthSummary
        let isProjectedTargetMet = (summary.totalHours + draftHours) >= summary.targetHours

        return ESStatusBanner(
            title: "保存后\(projectedMonthLabel)共 \(hoursText(summary.totalHours + draftHours)) / \(hoursText(summary.targetHours))h",
            message: isProjectedTargetMet ? "可达到 70% 目标" : "仍未达标",
            systemImage: isProjectedTargetMet ? "checkmark.seal.fill" : "scope",
            tone: isProjectedTargetMet ? .success : .warning
        )
    }

    // MARK: - Entries

    private var currentMonthEntriesCard: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            ESSectionHeader(
                title: "本月记录",
                trailing: "\(viewModel.currentMonthEntries.count)"
            )

            VStack(spacing: ESUI.Space.xs) {
                ForEach(viewModel.currentMonthEntries) { entry in
                    HStack(spacing: ESUI.Space.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entryTitle(for: entry))
                                .font(.subheadline.weight(.semibold))
                            if !entry.machine.isEmpty {
                                Text(entry.machine)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: ESUI.Space.sm)

                        Text("\(hoursText(entry.hours))h")
                            .font(.body.weight(.semibold).monospacedDigit())

                        Menu {
                            Button("删除", systemImage: "trash", role: .destructive) {
                                viewModel.deleteEntry(entry)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, ESUI.Space.md)
                    .padding(.vertical, ESUI.Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                            .fill(ESUI.fill)
                    )
                }
            }
        }
        .esCard()
    }

    // MARK: - History

    private var historyDisclosure: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            DisclosureGroup("历史月份", isExpanded: $showingHistory) {
                VStack(spacing: ESUI.Space.md) {
                    ForEach(viewModel.recentMonthSummaries(limit: 6).dropFirst()) { summary in
                        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
                            HStack {
                                Text(monthRangeText(for: summary))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(hoursText(summary.totalHours))h")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                ESStatusBadge(
                                    text: summary.isTargetMet ? "达标" : "差 \(hoursText(summary.remainingToTarget))h",
                                    tone: summary.isTargetMet ? .success : .neutral
                                )
                            }

                            ProgressView(value: clamped(summary.targetProgress))
                                .tint(summary.isTargetMet ? .green : .orange)
                        }
                    }
                }
                .padding(.top, ESUI.Space.sm)
            }
            .font(.headline)
            .tint(.primary)
        }
        .esCard()
    }

    // MARK: - Helpers

    private var quickHourOptions: [Double] {
        [4, 6, 8, 10]
    }

    private var selectedMonthSummary: UTMonthSummary {
        viewModel.summary(for: selectedDate)
    }

    private var remainingSuggestionHours: Double? {
        let remaining = roundedToHalfHour(selectedMonthSummary.remainingToTarget)
        guard remaining >= 0.5, remaining <= 16, !quickHourOptions.contains(remaining) else {
            return nil
        }
        return remaining
    }

    private var projectedMonthLabel: String {
        viewModel.isInCurrentMonth(selectedDate) ? "本月" : "该月"
    }

    private var saveButtonTitle: String {
        "保存\(selectedDateTitle) \(hoursText(draftHours))h"
    }

    private var selectedDateTitle: String {
        if Calendar.utTracker.isDateInToday(selectedDate) {
            return "今天"
        }
        if Calendar.utTracker.isDateInYesterday(selectedDate) {
            return "昨天"
        }
        return selectedDate.formatted(.dateTime.month().day())
    }

    private func presetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            ESHaptics.selection()
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ESUI.Space.sm)
                .padding(.vertical, ESUI.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : ESUI.fill)
                )
                .animation(ESMotion.quick, value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func saveEntry() {
        viewModel.addEntry(date: selectedDate, hours: draftHours, note: draftNote, machine: selectedMachine)
        ESHaptics.success()
        selectedDate = Date()
        draftHours = UTTrackerMetrics.dailyReferenceHours
        draftNote = ""
        showingMoreOptions = false
    }

    private func addNewMachine() {
        if let added = viewModel.addMachine(newMachineName, factory: selectedFactory) {
            selectedMachine = added
            viewModel.rememberMachine(added)
            newMachineName = ""
            ESHaptics.success()
        }
    }

    private func monthRangeText(for summary: UTMonthSummary) -> String {
        let start = summary.monthStart.formatted(.dateTime.month().day())
        let end = summary.monthEnd.formatted(.dateTime.month().day())
        return "\(start) - \(end)"
    }

    private func entryTitle(for entry: UTEntry) -> String {
        if viewModel.isToday(entry.date) {
            return "今天"
        }
        return entry.date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    private func hoursText(_ hours: Double) -> String {
        hours.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    private func percentText(for progress: Double) -> String {
        let percent = progress * 100
        return percent.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func roundedToHalfHour(_ hours: Double) -> Double {
        (hours * 2).rounded() / 2
    }
}

#Preview {
    NavigationStack {
        UTTrackerView()
    }
}


struct UTFactoryHoursScene: UIViewRepresentable {
    let groups: [UTFactoryHoursGroup]

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X
        scnView.scene = makeScene()
        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        scnView.scene = makeScene()
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 4.2, 8.5)
        cameraNode.look(at: SCNVector3(0, 0.6, 0))
        scene.rootNode.addChildNode(cameraNode)

        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.color = UIColor(white: 0.5, alpha: 1.0)
        scene.rootNode.addChildNode(ambientNode)

        let allHours = groups.flatMap(\.totals).map(\.totalHours)
        let globalMaxHours = allHours.max() ?? 0.0

        let maxPillarHeight: Float = 2.4
        let minPillarHeight: Float = 0.12
        let floorWidth: Float = 3.6
        let floorHeight: Float = 0.08
        let floorLength: Float = 2.4
        let floorTopY: Float = floorHeight

        let centersX: [Float] = [-2.1, 2.1]
        let factoryColors: [UIColor] = [.systemBlue, .systemOrange]

        for (index, group) in groups.prefix(2).enumerated() {
            let centerX = index < centersX.count ? centersX[index] : (index == 0 ? -2.1 : 2.1)
            let color = index < factoryColors.count ? factoryColors[index] : .systemGray

            let floorGeometry = SCNBox(
                width: CGFloat(floorWidth),
                height: CGFloat(floorHeight),
                length: CGFloat(floorLength),
                chamferRadius: 0.04
            )
            floorGeometry.firstMaterial?.diffuse.contents = UIColor.secondarySystemFill
            floorGeometry.firstMaterial?.specular.contents = UIColor.white
            let floorNode = SCNNode(geometry: floorGeometry)
            floorNode.position = SCNVector3(centerX, floorHeight / 2.0, 0)
            scene.rootNode.addChildNode(floorNode)

            let factoryNameNode = createTextNode(text: group.factory, color: color, fontSize: 2.0, scale: 0.08, isBillboard: false)
            factoryNameNode.position = SCNVector3(centerX, floorHeight + 0.1, Float(floorLength / 2.0) - 0.25)
            factoryNameNode.eulerAngles.x = -.pi / 4.0
            scene.rootNode.addChildNode(factoryNameNode)

            let machineCount = group.totals.count
            if machineCount > 0 {
                let usableWidth: Float = floorWidth - 0.8
                let step: Float = machineCount > 1 ? min(usableWidth / Float(machineCount - 1), 0.7) : 0.0
                let startX: Float = centerX - Float(machineCount - 1) * step / 2.0
                let pillarSize: CGFloat = machineCount > 5 ? 0.26 : 0.34

                for (mIndex, total) in group.totals.enumerated() {
                    let posX = startX + Float(mIndex) * step
                    let posZ: Float = 0.0

                    let pillarHeight: Float
                    if total.totalHours > 0 && globalMaxHours > 0 {
                        pillarHeight = max(minPillarHeight, Float(total.totalHours / globalMaxHours) * maxPillarHeight)
                    } else {
                        pillarHeight = minPillarHeight
                    }

                    let pillarGeometry = SCNBox(
                        width: pillarSize,
                        height: CGFloat(pillarHeight),
                        length: pillarSize,
                        chamferRadius: 0.03
                    )
                    pillarGeometry.firstMaterial?.diffuse.contents = color
                    pillarGeometry.firstMaterial?.specular.contents = UIColor.white

                    let pillarNode = SCNNode(geometry: pillarGeometry)
                    pillarNode.position = SCNVector3(posX, floorTopY + pillarHeight / 2.0, posZ)
                    scene.rootNode.addChildNode(pillarNode)

                    let labelNode = createTextNode(
                        text: total.machine,
                        color: .label,
                        fontSize: 2.0,
                        scale: 0.08,
                        isBillboard: true
                    )
                    labelNode.position = SCNVector3(posX, floorTopY + pillarHeight + 0.2, posZ)
                    scene.rootNode.addChildNode(labelNode)
                }
            }
        }

        return scene
    }

    private func createTextNode(
        text: String,
        color: UIColor,
        fontSize: CGFloat = 2.0,
        scale: Float = 0.08,
        isBillboard: Bool = false
    ) -> SCNNode {
        let scnText = SCNText(string: text, extrusionDepth: 0.2)
        scnText.font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        scnText.firstMaterial?.diffuse.contents = color
        scnText.firstMaterial?.isDoubleSided = true

        let textNode = SCNNode(geometry: scnText)
        textNode.scale = SCNVector3(scale, scale, scale)

        let (minVec, maxVec) = textNode.boundingBox
        let dx = (maxVec.x - minVec.x) / 2.0 + minVec.x
        let dy = (maxVec.y - minVec.y) / 2.0 + minVec.y
        let dz = (maxVec.z - minVec.z) / 2.0 + minVec.z
        textNode.pivot = SCNMatrix4MakeTranslation(dx, dy, dz)

        if isBillboard {
            let constraint = SCNBillboardConstraint()
            constraint.freeAxes = .Y
            textNode.constraints = [constraint]
        }

        return textNode
    }
}
