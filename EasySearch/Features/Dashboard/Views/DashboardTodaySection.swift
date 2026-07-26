import SwiftUI
import UIKit

/// 工作台顶部"今日"仪表盘:UT 进度 / 训练打卡 / 报销逾期,可直接操作。
struct DashboardTodaySection: View {
    let onOpenFeature: (String) -> Void

    @EnvironmentObject private var statusCenter: FeatureStatusCenter
    @EnvironmentObject private var navigationState: AppNavigationState
    @StateObject private var utViewModel = UTTrackerViewModel()
    @StateObject private var trainingViewModel = TrainingLogViewModel()
    @StateObject private var expenseViewModel = ExpenseAssistantViewModel()
    @State private var showingExpenseConfirm = false
    @State private var utLoggedToday = false

    var body: some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            Text("今日")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            utCard
            trainingCard

            if overdueCount > 0 {
                expenseCard
            }

            attentionBanner
        }
        .confirmationDialog(
            "把所有逾期项标记为已完成?",
            isPresented: $showingExpenseConfirm,
            titleVisibility: .visible
        ) {
            Button("全部标记已完成") {
                expenseViewModel.markAllOverdueSubmitted()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - UT

    private var utCard: some View {
        let summary = utViewModel.currentMonthSummary
        let progress = min(max(summary.elapsedMonthProgress, 0), 1)

        return Button {
            onOpenFeature("uttracker")
        } label: {
            HStack(spacing: ESUI.Space.md) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            summary.isTargetMet ? Color.green : Color.orange,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((summary.elapsedMonthProgress * 100).rounded()))%")
                        .font(.caption.weight(.bold).monospacedDigit())
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text("UT 记录")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(utDetailText(summary))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: ESUI.Space.xs)

                Button {
                    logDefaultHoursToday()
                } label: {
                    Text(utLoggedToday ? "已记 ✓" : "今天 +8h")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glass)
                .disabled(utLoggedToday)
            }
            .padding(ESUI.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                    .fill(ESUI.surface)
            )
        }
        .buttonStyle(ESCardButtonStyle())
        .onAppear { refreshUTLoggedToday() }
    }

    private func utDetailText(_ summary: UTMonthSummary) -> String {
        if summary.isTargetMet {
            return "本月已达标 · \(trimmedHours(summary.totalHours))h"
        }
        return "距 70% 目标还差 \(trimmedHours(summary.remainingToTarget))h"
    }

    private func logDefaultHoursToday() {
        utViewModel.addEntry(date: Date(), hours: UTTrackerMetrics.dailyReferenceHours, note: "")
        utLoggedToday = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func refreshUTLoggedToday() {
        let calendar = Calendar.utTracker
        utLoggedToday = utViewModel.currentMonthEntries.contains { calendar.isDateInToday($0.date) }
    }

    // MARK: - Training

    private var trainingCard: some View {
        let todayLines = trainingViewModel.lineCount(on: Date())
        let trainedToday = todayLines > 0
        let hasHistory = trainingViewModel.lastTrainedDay(before: Date()) != nil

        return Button {
            onOpenFeature("training-log")
        } label: {
            HStack(spacing: ESUI.Space.md) {
                ESFeatureIcon(
                    systemName: trainedToday ? "flame.fill" : "flame",
                    color: trainedToday ? .red : .secondary,
                    size: 52
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("训练记录")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(trainedToday
                         ? "今天已练 \(todayLines) 组 · 本月 \(trainingViewModel.monthTrainingDayCount) 天"
                         : "今天还没练 · 本月 \(trainingViewModel.monthTrainingDayCount) 天")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: ESUI.Space.xs)

                Button {
                    if hasHistory {
                        trainingViewModel.jumpToToday()
                        if trainingViewModel.repeatLastWorkout() {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    } else {
                        onOpenFeature("training-log")
                    }
                } label: {
                    Text(hasHistory ? "重复上次" : "去记录")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glass)
            }
            .padding(ESUI.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                    .fill(ESUI.surface)
            )
        }
        .buttonStyle(ESCardButtonStyle())
    }

    // MARK: - Expense

    private var overdueCount: Int {
        expenseViewModel.overdueMonthlyClaims.count + expenseViewModel.overdueTravelClaims.count
    }

    private var expenseCard: some View {
        Button {
            onOpenFeature("expense-assistant")
        } label: {
            HStack(spacing: ESUI.Space.md) {
                ESFeatureIcon(systemName: "receipt", color: .orange, size: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text("报销逾期")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("共 \(overdueCount) 项待处理")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: ESUI.Space.xs)

                Button {
                    showingExpenseConfirm = true
                } label: {
                    Text("全部已完成")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glass)
            }
            .padding(ESUI.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ESUI.cardCornerRadius, style: .continuous)
                    .fill(ESUI.surface)
            )
        }
        .buttonStyle(ESCardButtonStyle())
    }

    // MARK: - Attention

    @ViewBuilder
    private var attentionBanner: some View {
        if statusCenter.cloudSummary.kind == .recoverableFailure
            || statusCenter.cloudSummary.kind == .offlineOrUnavailable {
            Button {
                navigationState.openSettings(.cloudSync)
            } label: {
                ESStatusBanner(
                    title: "云同步异常:\(statusCenter.cloudSummary.text)",
                    systemImage: "icloud.slash",
                    tone: .danger
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func trimmedHours(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }
}
