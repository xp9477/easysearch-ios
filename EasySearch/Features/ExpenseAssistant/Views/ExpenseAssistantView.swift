import SwiftUI

public struct ExpenseAssistantView: View {
    @StateObject private var viewModel = ExpenseAssistantViewModel()
    @StateObject private var notificationManager = ExpenseAssistantNotificationManager.shared
    @State private var showingAddTravelSheet = false

    public init() {}

    public var body: some View {
        List {
            overviewSection
            monthlySection
            travelSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("报销助手")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddTravelSheet = true
                } label: {
                    Label("新增出差", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddTravelSheet) {
            AddTravelClaimSheet(viewModel: viewModel)
        }
        .navigationDestination(for: MonthlyExpenseClaim.self) { claim in
            MonthlyClaimDetailView(viewModel: viewModel, claimID: claim.id)
        }
        .navigationDestination(for: TravelExpenseClaim.self) { claim in
            TravelClaimDetailView(viewModel: viewModel, claimID: claim.id)
        }
        .task {
            viewModel.refreshIfNeeded()
            await notificationManager.configure()
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: ESUI.Space.md) {
                HStack(alignment: .top, spacing: ESUI.Space.sm) {
                    VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                        Text("逾期概览")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("未完成的上月月单和已结束出差会进入每日提醒。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: ESUI.Space.xs)

                    Text("\(viewModel.overdueMonthlyClaims.count + viewModel.overdueTravelClaims.count)")
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityLabel(
                            "逾期 \(viewModel.overdueMonthlyClaims.count + viewModel.overdueTravelClaims.count) 项"
                        )
                }

                HStack(spacing: ESUI.Space.sm) {
                    summaryChip(
                        title: "月单",
                        value: "\(viewModel.overdueMonthlyClaims.count) 项",
                        tone: .warning
                    )
                    summaryChip(
                        title: "出差",
                        value: "\(viewModel.overdueTravelClaims.count) 项",
                        tone: .accent
                    )
                }

                ESStatusBanner(
                    title: nextReminderText,
                    systemImage: "bell.badge",
                    tone: notificationManager.notificationsEnabled ? .neutral : .warning
                )
            }
            .padding(.vertical, ESUI.Space.xs)
            .listRowInsets(
                EdgeInsets(
                    top: ESUI.Space.sm,
                    leading: ESUI.Space.md,
                    bottom: ESUI.Space.xs,
                    trailing: ESUI.Space.md
                )
            )
        }
    }

    private var monthlySection: some View {
        Section {
            if viewModel.monthlyClaims.isEmpty {
                ESEmptyState(
                    title: "暂无月度报销",
                    message: "系统会按月份自动生成月单。",
                    systemImage: "calendar"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.monthlyClaims) { claim in
                    NavigationLink(value: claim) {
                        MonthlyClaimRow(
                            claim: claim,
                            isOverdue: viewModel.overdueMonthlyClaimIDs.contains(claim.id)
                        )
                    }
                }
            }
        } header: {
            Text("月度报销")
        }
    }

    private var travelSection: some View {
        Section {
            if viewModel.travelClaims.isEmpty {
                ESEmptyState(
                    title: "还没有出差报销单",
                    message: "点右上角新增出差，开始跟踪审批与报销项。",
                    systemImage: "airplane"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.travelClaims) { claim in
                    NavigationLink(value: claim) {
                        TravelClaimRow(
                            claim: claim,
                            isOverdue: viewModel.overdueTravelClaimIDs.contains(claim.id)
                        )
                    }
                }
            }
        } header: {
            Text("出差报销")
        }
    }

    private var nextReminderText: String {
        guard notificationManager.notificationsEnabled else {
            return "通知未开启"
        }

        guard let nextReminderDate = viewModel.nextReminderDate else {
            return "当前没有待提醒报销单"
        }

        return "下次提醒：\(nextReminderDate.formatted(.dateTime.month().day().hour().minute()))"
    }

    private func summaryChip(title: String, value: String, tone: ESStatusBadge.Tone) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ESUI.Space.sm)
        .padding(.vertical, ESUI.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: ESUI.compactCornerRadius, style: .continuous)
                .fill(tone.color.opacity(0.12))
        )
    }
}

// MARK: - Rows

private struct MonthlyClaimRow: View {
    let claim: MonthlyExpenseClaim
    let isOverdue: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            HStack(spacing: ESUI.Space.xs) {
                Text(claim.monthStart.formatted(.dateTime.year().month()))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                if isOverdue {
                    ESStatusBadge(text: "逾期", tone: .warning)
                } else if claim.isCompleted {
                    ESStatusBadge(text: "已完成", tone: .success)
                }
            }

            Text(claimSummaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, ESUI.Space.xxs)
    }

    private var claimSummaryText: String {
        if claim.isCompleted {
            return "4 项已处理完成"
        }

        return "\(claim.completedItemCount)/4 项已处理"
    }
}

private struct TravelClaimRow: View {
    let claim: TravelExpenseClaim
    let isOverdue: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.xs) {
            HStack(spacing: ESUI.Space.xs) {
                Text(claim.resolvedTitle())
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if isOverdue {
                    ESStatusBadge(text: "逾期", tone: .warning)
                } else if claim.isCompleted {
                    ESStatusBadge(text: "已完成", tone: .success)
                }
            }

            Text(dateSummaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(statusSummaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, ESUI.Space.xxs)
    }

    private var dateSummaryText: String {
        let startText = claim.startDate.formatted(.dateTime.month().day().hour().minute())
        guard let endDate = claim.endDate else {
            return "开始：\(startText) · 结束时间未填写"
        }
        return "开始：\(startText) · 结束：\(endDate.formatted(.dateTime.month().day().hour().minute()))"
    }

    private var statusSummaryText: String {
        "TA \(claim.travelApprovalStatus.title) · Per Diem \(claim.perDiemStatus.title) · Expense \(claim.expenseStatus.title)"
    }
}

// MARK: - Detail

private struct MonthlyClaimDetailView: View {
    @ObservedObject var viewModel: ExpenseAssistantViewModel
    let claimID: String

    var body: some View {
        Group {
            if let claim = viewModel.monthlyClaim(id: claimID) {
                List {
                    Section {
                        ESValueRow(
                            title: "月份",
                            value: claim.monthStart.formatted(.dateTime.year().month())
                        )
                        ESValueRow(
                            title: "完成情况",
                            value: claim.isCompleted ? "已完成" : "\(claim.completedItemCount)/4 项已处理"
                        )
                    }

                    Section("报销项") {
                        ForEach(MonthlyExpenseField.allCases) { field in
                            Picker(field.title, selection: binding(for: field)) {
                                ForEach(ExpenseClaimItemStatus.allCases) { status in
                                    Text(status.title).tag(status)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                .navigationTitle(claim.monthStart.formatted(.dateTime.year().month()))
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ESErrorState(title: "月度报销单不存在", message: "该单据可能已被删除。")
            }
        }
    }

    private func binding(for field: MonthlyExpenseField) -> Binding<ExpenseClaimItemStatus> {
        Binding {
            viewModel.monthlyClaim(id: claimID)?.status(for: field) ?? .pending
        } set: { newValue in
            viewModel.updateMonthlyStatus(claimID: claimID, field: field, status: newValue)
        }
    }
}

private struct TravelClaimDetailView: View {
    @ObservedObject var viewModel: ExpenseAssistantViewModel
    let claimID: UUID

    var body: some View {
        Group {
            if let claim = viewModel.travelClaim(id: claimID) {
                List {
                    Section("基本信息") {
                        TextField(
                            "出差标题（可选）",
                            text: Binding(
                                get: { viewModel.travelClaim(id: claimID)?.title ?? "" },
                                set: { viewModel.updateTravelTitle(claimID: claimID, title: $0) }
                            )
                        )

                        DatePicker(
                            "开始时间",
                            selection: Binding(
                                get: { viewModel.travelClaim(id: claimID)?.startDate ?? claim.startDate },
                                set: { viewModel.updateTravelStartDate(claimID: claimID, startDate: $0) }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        Toggle(
                            "已填写结束时间",
                            isOn: Binding(
                                get: { viewModel.travelClaim(id: claimID)?.endDate != nil },
                                set: { isOn in
                                    let claim = viewModel.travelClaim(id: claimID)
                                    let defaultEndDate = claim?.endDate ?? claim?.startDate ?? Date()
                                    viewModel.updateTravelEndDate(
                                        claimID: claimID,
                                        endDate: isOn ? defaultEndDate : nil
                                    )
                                }
                            )
                        )

                        if claim.endDate != nil {
                            DatePicker(
                                "结束时间",
                                selection: Binding(
                                    get: { viewModel.travelClaim(id: claimID)?.endDate ?? claim.startDate },
                                    set: { viewModel.updateTravelEndDate(claimID: claimID, endDate: $0) }
                                ),
                                in: claim.startDate...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    }

                    Section("TA") {
                        Picker(
                            "Travel Approval",
                            selection: Binding(
                                get: { viewModel.travelClaim(id: claimID)?.travelApprovalStatus ?? .pending },
                                set: { viewModel.updateTravelApprovalStatus(claimID: claimID, status: $0) }
                            )
                        ) {
                            ForEach(TravelApprovalStatus.allCases) { status in
                                Text(status.title).tag(status)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section("报销项") {
                        ForEach(TravelExpenseField.allCases) { field in
                            Picker(
                                field.title,
                                selection: Binding(
                                    get: { viewModel.travelClaim(id: claimID)?.status(for: field) ?? .pending },
                                    set: { viewModel.updateTravelStatus(claimID: claimID, field: field, status: $0) }
                                )
                            ) {
                                ForEach(ExpenseClaimItemStatus.allCases) { status in
                                    Text(status.title).tag(status)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Section {
                        ESValueRow(
                            title: "整单状态",
                            value: claim.isCompleted ? "已完成" : "待处理"
                        )
                    }
                }
                .navigationTitle(claim.resolvedTitle())
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ESErrorState(title: "出差报销单不存在", message: "该单据可能已被删除。")
            }
        }
    }
}

// MARK: - Sheet

private struct AddTravelClaimSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseAssistantViewModel
    @State private var title = ""
    @State private var startDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("出差标题（可选）", text: $title)
                    DatePicker("开始时间", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("新增出差")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        viewModel.addTravelClaim(title: title, startDate: startDate)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ExpenseAssistantView()
    }
}
