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

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("逾期概览")
                            .font(.system(size: 22, weight: .bold))
                        Text("未完成的上月月单和已结束出差会进入每日提醒。")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(viewModel.overdueMonthlyClaims.count + viewModel.overdueTravelClaims.count)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 12) {
                    summaryChip(
                        title: "月单",
                        value: "\(viewModel.overdueMonthlyClaims.count) 项",
                        color: .orange
                    )
                    summaryChip(
                        title: "出差",
                        value: "\(viewModel.overdueTravelClaims.count) 项",
                        color: .blue
                    )
                }

                HStack(spacing: 10) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.tint)
                    Text(nextReminderText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.secondarySystemGroupedBackground),
                                Color.orange.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var monthlySection: some View {
        Section("月度报销") {
            ForEach(viewModel.monthlyClaims) { claim in
                NavigationLink(value: claim) {
                    MonthlyClaimRow(
                        claim: claim,
                        isOverdue: viewModel.overdueMonthlyClaimIDs.contains(claim.id)
                    )
                }
            }
        }
    }

    private var travelSection: some View {
        Section("出差报销") {
            if viewModel.travelClaims.isEmpty {
                Label("还没有出差报销单", systemImage: "airplane")
                    .foregroundStyle(.secondary)
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

    private func summaryChip(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }
}

private struct MonthlyClaimRow: View {
    let claim: MonthlyExpenseClaim
    let isOverdue: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(claim.monthStart.formatted(.dateTime.year().month()))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                if isOverdue {
                    statusBadge(title: "逾期", color: .orange)
                } else if claim.isCompleted {
                    statusBadge(title: "已完成", color: .green)
                }
            }

            Text(claimSummaryText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var claimSummaryText: String {
        if claim.isCompleted {
            return "4 项已处理完成"
        }

        return "\(claim.completedItemCount)/4 项已处理"
    }

    private func statusBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .foregroundStyle(color)
    }
}

private struct TravelClaimRow: View {
    let claim: TravelExpenseClaim
    let isOverdue: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(claim.resolvedTitle())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if isOverdue {
                    statusBadge(title: "逾期", color: .orange)
                } else if claim.isCompleted {
                    statusBadge(title: "已完成", color: .green)
                }
            }

            Text(dateSummaryText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(statusSummaryText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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

    private func statusBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .foregroundStyle(color)
    }
}

private struct MonthlyClaimDetailView: View {
    @ObservedObject var viewModel: ExpenseAssistantViewModel
    let claimID: String

    var body: some View {
        Group {
            if let claim = viewModel.monthlyClaim(id: claimID) {
                List {
                    Section {
                        LabeledContent("月份", value: claim.monthStart.formatted(.dateTime.year().month()))
                        LabeledContent("完成情况", value: claim.isCompleted ? "已完成" : "\(claim.completedItemCount)/4 项已处理")
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
                missingState(title: "月度报销单不存在")
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
                                get: { viewModel.travelClaim(id: claimID)?.startDate ?? Date() },
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
                        LabeledContent("整单状态", value: claim.isCompleted ? "已完成" : "待处理")
                    }
                }
                .navigationTitle(claim.resolvedTitle())
                .navigationBarTitleDisplayMode(.inline)
            } else {
                missingState(title: "出差报销单不存在")
            }
        }
    }
}

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

private func missingState(title: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: "exclamationmark.circle")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.secondary)
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
}
