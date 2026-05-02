import SwiftUI
import WebKit
import AVKit
@preconcurrency import AVFoundation
import UIKit

struct HiddenJavDBWatchSite: Identifiable, Hashable {
    enum LaunchMode: Equatable {
        case nativeStream
        case embeddedWeb
        case external
    }

    let name: String
    let urlTemplate: String
    var id: String { name }

    static var missAV: HiddenJavDBWatchSite {
        HiddenJavDBWatchSite(name: "MISSAV", urlTemplate: HiddenMissAVDomainConfiguration.currentMovieTemplate())
    }

    static var defaultSites: [HiddenJavDBWatchSite] {
        [.missAV]
    }

    var launchMode: LaunchMode {
        switch name {
        case "MISSAV":
            return .nativeStream
        case "Jav.Guru":
            return .embeddedWeb
        default:
            return .external
        }
    }

    func url(for rawCode: String) -> URL? {
        let code = HiddenJavDBWatchSite.normalizedCode(rawCode)
        guard !code.isEmpty else { return nil }
        let formattedCode: String
        if name == "FANZA 動画" {
            formattedCode = HiddenJavDBWatchSite.fanzaCode(from: code)
        } else if name == "JavBus" && code.uppercased().hasPrefix("MIUM") {
            formattedCode = "300" + code
        } else {
            formattedCode = code
        }
        let urlString = urlTemplate.replacingOccurrences(of: "{{code}}", with: formattedCode)
        return URL(string: urlString)
    }

    private static func normalizedCode(_ rawCode: String) -> String {
        rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private static func fanzaCode(from code: String) -> String {
        let parts = code.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return code.lowercased() }
        let prefix = parts[0].lowercased()
        let numberPart = parts[1]
        let number = numberPart.count < 5
            ? String(repeating: "0", count: 5 - numberPart.count) + numberPart
            : numberPart
        if prefix.hasPrefix("start") {
            return "1\(prefix)\(number)"
        }
        return "\(prefix)\(number)"
    }
}

private struct HiddenInAppPlayerItem: Identifiable, Hashable {
    let movie: HiddenJavDBMovie
    let sourceName: String
    let streamURL: URL
    let refererURL: URL
    let startPositionSeconds: Double
    let markerPositions: [Double]
    let id = UUID()
}

private struct HiddenInAppWebPageItem: Identifiable, Hashable {
    let title: String
    let url: URL
    let id = UUID()
}

private struct HiddenInAppVideoPlayerView: View {
    private enum SurfaceInteractionMode {
        case undecided
        case brightnessAdjusting
    }

    let item: HiddenInAppPlayerItem
    let onSaveFavoritePlayback: (HiddenJavDBFavoritePlayback) -> HiddenJavDBFavoritePlaybackSaveContext
    let onUndoFavoritePlaybackSave: (HiddenJavDBFavoritePlaybackSaveContext) -> [Double]

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var appliedPlaybackRate: Float = 1.0
    @State private var isMuted = true
    @State private var showUnmuteConfirm = false
    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var isProgrammaticSeeking = false
    @State private var controlsVisible = true
    @State private var controlsAutoHideTask: Task<Void, Never>?
    @State private var seekTask: Task<Void, Never>?
    @State private var favoriteSaveResetTask: Task<Void, Never>?
    @State private var recentlySavedPlaybackContext: HiddenJavDBFavoritePlaybackSaveContext?
    @State private var recentlySavedPosition: Double?
    @State private var favoriteUndoCountdown = 0
    @State private var isTemporaryBoostActive = false
    @State private var playbackRateRampTask: Task<Void, Never>?
    @State private var pendingBoostActivationTask: Task<Void, Never>?
    @State private var activeTouchStartedAt: Date?
    @State private var activeTouchStartLocation: CGPoint?
    @State private var didActivateTouchBoost = false
    @State private var surfaceInteractionMode: SurfaceInteractionMode = .undecided
    @State private var touchStartBrightness: CGFloat?
    @State private var displayedBrightness: CGFloat?
    @State private var didApplyInitialStartPosition = false
    @State private var markerPositions: [Double]

    private let normalPlaybackRate: Float = 1.0
    private let temporaryBoostRate: Float = 2.0
    private let boostActivationDelay: TimeInterval = 0.18
    private let boostActivationMaximumDistance: CGFloat = 36
    private let tapMaximumDistance: CGFloat = 12
    private let playbackRateRampDuration: TimeInterval = 0.28
    private let brightnessGestureLeadingRegionRatio: CGFloat = 0.42
    private let brightnessActivationMinimumDistance: CGFloat = 14

    init(
        item: HiddenInAppPlayerItem,
        onSaveFavoritePlayback: @escaping (HiddenJavDBFavoritePlayback) -> HiddenJavDBFavoritePlaybackSaveContext,
        onUndoFavoritePlaybackSave: @escaping (HiddenJavDBFavoritePlaybackSaveContext) -> [Double]
    ) {
        self.item = item
        self.onSaveFavoritePlayback = onSaveFavoritePlayback
        self.onUndoFavoritePlaybackSave = onUndoFavoritePlaybackSave

        let headers: [String: String] = [
            "Referer": item.refererURL.absoluteString,
            "Origin": "\(item.refererURL.scheme ?? "https")://\(item.refererURL.host ?? HiddenMissAVDomainConfiguration.currentHost())",
            "User-Agent": HiddenJavDBAPI.userAgent
        ]
        let asset = AVURLAsset(
            url: item.streamURL,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": headers
            ]
        )
        let playerItem = AVPlayerItem(asset: asset)
        _player = State(initialValue: AVPlayer(playerItem: playerItem))
        _markerPositions = State(initialValue: Self.normalizedMarkerPositions(item.markerPositions))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HiddenAVPlayerContainerView(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            GeometryReader { proxy in
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(videoSurfaceGesture(in: proxy.size))
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topOverlay
                Spacer()
                centerControls
                Spacer()
                bottomOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)

            if shouldShowPlaybackRateHUD {
                playbackRateHUD
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if shouldShowBrightnessHUD {
                brightnessHUD
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: shouldShowPlaybackRateHUD)
        .animation(.easeInOut(duration: 0.18), value: shouldShowBrightnessHUD)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            configureAudioSession()
            player.isMuted = true
            applyPlayerRateImmediately(normalPlaybackRate)
            player.playImmediately(atRate: appliedPlaybackRate)
            syncPlaybackState()
            scheduleControlsAutoHide()
        }
        .onDisappear {
            seekTask?.cancel()
            controlsAutoHideTask?.cancel()
            favoriteSaveResetTask?.cancel()
            pendingBoostActivationTask?.cancel()
            playbackRateRampTask?.cancel()
            isTemporaryBoostActive = false
            displayedBrightness = nil
            player.pause()
        }
        .task(id: item.id) {
            await applyInitialStartPositionIfNeeded()
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            syncPlaybackState()
        }
        .alert("开启声音", isPresented: $showUnmuteConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认") {
                isMuted = false
                player.isMuted = false
                scheduleControlsAutoHide()
            }
        } message: {
            Text("播放器默认静音。确认后将开启声音。")
        }
    }

    private var topOverlay: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.72), Color.black.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 132)
            .overlay(alignment: .top) {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.movie.displayTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            playerBadge(text: item.sourceName)
                            playerBadge(text: item.movie.code)
                            playerBadge(text: formattedRate(appliedPlaybackRate))
                            if !markerPositions.isEmpty {
                                playerBadge(text: "\(markerPositions.count) 个点")
                            }
                            if isMuted {
                                playerBadge(text: "静音")
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
        }
        .allowsHitTesting(true)
    }

    private var centerControls: some View {
        HStack(spacing: 26) {
            largeCircleButton(systemImage: "gobackward.15") {
                seek(by: -15)
            }

            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 72, height: 72)
                    .background(Color.white, in: Circle())
                    .shadow(color: Color.black.opacity(0.35), radius: 18, y: 10)
            }
            .buttonStyle(.plain)

            largeCircleButton(systemImage: "goforward.15") {
                seek(by: 15)
            }
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.2), Color.black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 248)
            .overlay(alignment: .bottom) {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        HStack {
                            Text(formattedDuration(isScrubbing ? scrubPosition : currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.88))
                            Spacer()
                            Text(formattedDuration(duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.88))
                        }

                        Slider(
                            value: Binding(
                                get: { isScrubbing ? scrubPosition : currentTime },
                                set: { scrubPosition = $0 }
                            ),
                            in: 0...max(duration, 1),
                            onEditingChanged: handleScrub(editing:)
                        )
                        .tint(.white)
                        .overlay {
                            HiddenPlaybackMarkerTrackView(
                                markerPositions: markerPositions,
                                duration: duration
                            )
                            .padding(.horizontal, 12)
                            .allowsHitTesting(false)
                        }
                    }

                    HStack(spacing: 10) {
                        compactSeekButton(title: "-1m", systemImage: "backward.fill") {
                            seek(by: -60)
                        }
                        compactSeekButton(title: "+1m", systemImage: "forward.fill") {
                            seek(by: 60)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            saveFavoritePlaybackPosition()
                        } label: {
                            Label(recentlySavedPlaybackContext == nil ? "喜欢此处" : "已记录", systemImage: recentlySavedPlaybackContext == nil ? "heart.fill" : "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            toggleMute()
                        } label: {
                            Label(isMuted ? "开启声音" : "静音", systemImage: isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Text("左侧上下滑动调亮度，长按画面可临时 2x 播放。")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let recentlySavedPosition, recentlySavedPlaybackContext != nil {
                        HStack(spacing: 10) {
                            Text("已记录 \(HiddenPlaybackTimeFormatter.string(from: recentlySavedPosition))，\(max(favoriteUndoCountdown, 1)) 秒内可撤回")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.76))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("撤回") {
                                undoFavoritePlaybackSave()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func playerBadge(text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func largeCircleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.black.opacity(0.42), in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var shouldShowPlaybackRateHUD: Bool {
        abs(appliedPlaybackRate - normalPlaybackRate) > 0.05
    }

    private var playbackRateHUD: some View {
        VStack {
            Text(formattedRate(appliedPlaybackRate))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isTemporaryBoostActive ? Color.orange.opacity(0.86) : Color.black.opacity(0.56))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
            Spacer()
        }
        .padding(.top, controlsVisible ? 94 : 54)
        .allowsHitTesting(false)
    }

    private var shouldShowBrightnessHUD: Bool {
        displayedBrightness != nil
    }

    private var brightnessHUD: some View {
        VStack {
            Spacer()

            HStack {
                VStack(spacing: 10) {
                    Image(systemName: "sun.max.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(formattedBrightness(displayedBrightness ?? UIScreen.main.brightness))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)

                    GeometryReader { proxy in
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))

                            Capsule()
                                .fill(Color.white)
                                .frame(height: max(12, proxy.size.height * (displayedBrightness ?? UIScreen.main.brightness)))
                        }
                    }
                    .frame(width: 8, height: 88)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

                Spacer()
            }
            .padding(.leading, 18)
            .padding(.bottom, controlsVisible ? 168 : 84)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func compactSeekButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
            controlsAutoHideTask?.cancel()
        } else {
            player.playImmediately(atRate: appliedPlaybackRate)
            isPlaying = true
            scheduleControlsAutoHide()
        }
    }

    private func toggleMute() {
        if isMuted {
            showUnmuteConfirm = true
        } else {
            isMuted = true
            player.isMuted = true
            scheduleControlsAutoHide()
        }
    }

    private func seek(by seconds: Double) {
        let baseTime = resolvedCurrentPlaybackTime
        guard baseTime.isFinite else { return }

        var target = max(0, baseTime + seconds)
        if duration.isFinite, duration > 0 {
            target = min(target, duration)
        }

        updateDisplayedPlaybackPosition(to: target)
        seekPlayer(to: target)
        showControlsTemporarily()
    }

    private func formattedRate(_ value: Float) -> String {
        let roundedValue = round(value)
        if abs(value - roundedValue) < 0.05 {
            return "\(Int(roundedValue))x"
        }
        return String(format: "%.1fx", value)
    }

    private func formattedBrightness(_ value: CGFloat) -> String {
        "\(Int(round(value * 100)))%"
    }

    private func formattedDuration(_ seconds: Double) -> String {
        HiddenPlaybackTimeFormatter.string(from: seconds)
    }

    private func handleScrub(editing: Bool) {
        isScrubbing = editing

        if editing {
            seekTask?.cancel()
            isProgrammaticSeeking = false
            controlsAutoHideTask?.cancel()
            scrubPosition = currentTime
            return
        }

        let target = normalizedPlaybackTime(scrubPosition)
        updateDisplayedPlaybackPosition(to: target)
        seekPlayer(to: target)
    }

    private func syncPlaybackState() {
        let latestDuration = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)
        if latestDuration.isFinite, latestDuration > 0 {
            duration = latestDuration
        }

        let latestTime = CMTimeGetSeconds(player.currentTime())
        if latestTime.isFinite, !isProgrammaticSeeking {
            let normalizedTime = normalizedPlaybackTime(latestTime)
            currentTime = normalizedTime
            if !isScrubbing {
                scrubPosition = normalizedTime
            }
        }

        isPlaying = player.timeControlStatus == .playing
    }

    private func toggleControlsVisibility() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }

        if controlsVisible {
            scheduleControlsAutoHide()
        } else {
            controlsAutoHideTask?.cancel()
        }
    }

    private func showControlsTemporarily() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }
        scheduleControlsAutoHide()
    }

    private func scheduleControlsAutoHide() {
        controlsAutoHideTask?.cancel()
        guard isPlaying, !isScrubbing, !isProgrammaticSeeking else { return }

        controlsAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, isPlaying, !isScrubbing, !isProgrammaticSeeking else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = false
            }
        }
    }

    @MainActor
    private func applyInitialStartPositionIfNeeded() async {
        guard !didApplyInitialStartPosition, item.startPositionSeconds > 0.5 else { return }
        didApplyInitialStartPosition = true

        let targetTime = CMTime(seconds: item.startPositionSeconds, preferredTimescale: 600)
        isProgrammaticSeeking = true
        for _ in 0..<20 {
            if Task.isCancelled {
                isProgrammaticSeeking = false
                return
            }

            if player.currentItem?.status == .readyToPlay {
                await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                updateDisplayedPlaybackPosition(to: item.startPositionSeconds)
                isProgrammaticSeeking = false
                return
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        updateDisplayedPlaybackPosition(to: item.startPositionSeconds)
        isProgrammaticSeeking = false
    }

    private func saveFavoritePlaybackPosition() {
        let latestTime = isScrubbing ? scrubPosition : currentTime
        let positionSeconds = max(0, latestTime.isFinite ? latestTime : CMTimeGetSeconds(player.currentTime()))
        let playback = HiddenJavDBFavoritePlayback(
            movie: item.movie,
            sourceName: item.sourceName,
            streamURL: item.streamURL,
            refererURL: item.refererURL,
            positionSeconds: positionSeconds
        )

        let saveContext = onSaveFavoritePlayback(playback)
        markerPositions = Self.normalizedMarkerPositions(saveContext.markerPositions)
        recentlySavedPlaybackContext = saveContext
        recentlySavedPosition = saveContext.savedPlayback.positionSeconds
        scheduleFavoriteUndoCountdown()
        showControlsTemporarily()
    }

    private var targetPlaybackRate: Float {
        isTemporaryBoostActive ? temporaryBoostRate : normalPlaybackRate
    }

    private var resolvedCurrentPlaybackTime: Double {
        let candidate = isScrubbing ? scrubPosition : currentTime
        if candidate.isFinite {
            return normalizedPlaybackTime(candidate)
        }
        return normalizedPlaybackTime(CMTimeGetSeconds(player.currentTime()))
    }

    private func normalizedPlaybackTime(_ value: Double) -> Double {
        let nonNegativeValue = max(0, value.isFinite ? value : 0)
        guard duration.isFinite, duration > 0 else { return nonNegativeValue }
        return min(nonNegativeValue, duration)
    }

    private func updateDisplayedPlaybackPosition(to value: Double) {
        let normalizedValue = normalizedPlaybackTime(value)
        currentTime = normalizedValue
        scrubPosition = normalizedValue
    }

    private func seekPlayer(to target: Double) {
        seekTask?.cancel()
        isProgrammaticSeeking = true

        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        let resumePlayback = isPlaying
        let rateAfterSeek = appliedPlaybackRate

        seekTask = Task { @MainActor in
            await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled else { return }

            updateDisplayedPlaybackPosition(to: target)
            isProgrammaticSeeking = false

            if resumePlayback {
                player.playImmediately(atRate: rateAfterSeek)
            }
            scheduleControlsAutoHide()
        }
    }

    private func videoSurfaceGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                handleVideoSurfaceTouchChanged(value, in: size)
            }
            .onEnded { value in
                handleVideoSurfaceTouchEnded(value)
            }
    }

    private func applyPlayerRateImmediately(_ rate: Float) {
        let normalizedRate = max(0.25, rate)
        appliedPlaybackRate = normalizedRate
        player.defaultRate = normalizedRate
        if player.timeControlStatus == .playing {
            player.rate = normalizedRate
        }
    }

    private func rampPlaybackRate(to targetRate: Float) {
        playbackRateRampTask?.cancel()

        let clampedTargetRate = max(0.25, targetRate)
        let startRate = appliedPlaybackRate
        guard abs(startRate - clampedTargetRate) >= 0.02 else {
            applyPlayerRateImmediately(clampedTargetRate)
            return
        }

        playbackRateRampTask = Task { @MainActor in
            let startedAt = Date()

            while !Task.isCancelled {
                let progress = min(Date().timeIntervalSince(startedAt) / playbackRateRampDuration, 1)
                let easedProgress = 1 - pow(1 - progress, 3)
                let nextRate = startRate + (clampedTargetRate - startRate) * Float(easedProgress)
                applyPlayerRateImmediately(nextRate)

                if progress >= 1 {
                    break
                }

                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            guard !Task.isCancelled else { return }
            applyPlayerRateImmediately(clampedTargetRate)
        }
    }

    private func beginTemporarySpeedBoost() {
        guard !isTemporaryBoostActive else { return }
        isTemporaryBoostActive = true
        rampPlaybackRate(to: targetPlaybackRate)
    }

    private func endTemporarySpeedBoostIfNeeded() {
        guard isTemporaryBoostActive else { return }
        isTemporaryBoostActive = false
        rampPlaybackRate(to: targetPlaybackRate)
    }

    private func handleVideoSurfaceTouchChanged(_ value: DragGesture.Value, in size: CGSize) {
        if activeTouchStartedAt == nil {
            activeTouchStartedAt = Date()
            activeTouchStartLocation = value.startLocation
            surfaceInteractionMode = .undecided
            touchStartBrightness = UIScreen.main.brightness
            displayedBrightness = nil
            didActivateTouchBoost = false
            schedulePendingBoostActivation()
            return
        }

        guard let touchStartLocation = activeTouchStartLocation else { return }
        let horizontalDistance = abs(value.location.x - touchStartLocation.x)
        let verticalDistance = abs(value.location.y - touchStartLocation.y)

        if shouldBeginBrightnessAdjustment(
            from: touchStartLocation,
            in: size,
            horizontalDistance: horizontalDistance,
            verticalDistance: verticalDistance
        ) {
            beginBrightnessAdjustment()
        }

        if surfaceInteractionMode == .brightnessAdjusting {
            updateBrightness(with: value, in: size)
            return
        }

        let travelDistance = distanceBetween(value.location, and: touchStartLocation)

        if travelDistance > boostActivationMaximumDistance {
            pendingBoostActivationTask?.cancel()
            if isTemporaryBoostActive {
                endTemporarySpeedBoostIfNeeded()
            }
        }
    }

    private func handleVideoSurfaceTouchEnded(_ value: DragGesture.Value) {
        let touchStartedAt = activeTouchStartedAt
        let touchStartLocation = activeTouchStartLocation ?? value.startLocation
        let pressDuration = touchStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let travelDistance = distanceBetween(value.location, and: touchStartLocation)
        let shouldToggleControls = surfaceInteractionMode == .undecided && !didActivateTouchBoost && pressDuration < boostActivationDelay && travelDistance <= tapMaximumDistance

        pendingBoostActivationTask?.cancel()
        activeTouchStartedAt = nil
        activeTouchStartLocation = nil
        touchStartBrightness = nil
        displayedBrightness = nil
        surfaceInteractionMode = .undecided
        didActivateTouchBoost = false

        endTemporarySpeedBoostIfNeeded()

        if shouldToggleControls {
            toggleControlsVisibility()
        }
    }

    private func schedulePendingBoostActivation() {
        pendingBoostActivationTask?.cancel()
        pendingBoostActivationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(boostActivationDelay * 1_000_000_000))
            guard !Task.isCancelled, activeTouchStartedAt != nil, !didActivateTouchBoost else { return }
            didActivateTouchBoost = true
            beginTemporarySpeedBoost()
        }
    }

    private func distanceBetween(_ lhs: CGPoint, and rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func shouldBeginBrightnessAdjustment(
        from startLocation: CGPoint,
        in size: CGSize,
        horizontalDistance: CGFloat,
        verticalDistance: CGFloat
    ) -> Bool {
        guard surfaceInteractionMode == .undecided else { return false }
        guard startLocation.x <= size.width * brightnessGestureLeadingRegionRatio else { return false }
        guard verticalDistance >= brightnessActivationMinimumDistance else { return false }
        return verticalDistance > horizontalDistance * 1.2
    }

    private func beginBrightnessAdjustment() {
        pendingBoostActivationTask?.cancel()
        endTemporarySpeedBoostIfNeeded()
        surfaceInteractionMode = .brightnessAdjusting
    }

    private func updateBrightness(with value: DragGesture.Value, in size: CGSize) {
        guard let startLocation = activeTouchStartLocation, let startBrightness = touchStartBrightness else { return }
        let height = max(size.height, 1)
        let delta = (startLocation.y - value.location.y) / height
        let nextBrightness = min(max(startBrightness + delta, 0), 1)
        UIScreen.main.brightness = nextBrightness
        displayedBrightness = nextBrightness
    }

    private func scheduleFavoriteUndoCountdown() {
        favoriteSaveResetTask?.cancel()
        favoriteUndoCountdown = 3

        favoriteSaveResetTask = Task { @MainActor in
            for remaining in stride(from: 3, through: 1, by: -1) {
                favoriteUndoCountdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
            }

            recentlySavedPlaybackContext = nil
            recentlySavedPosition = nil
            favoriteUndoCountdown = 0
        }
    }

    private func undoFavoritePlaybackSave() {
        guard let context = recentlySavedPlaybackContext else { return }
        markerPositions = Self.normalizedMarkerPositions(onUndoFavoritePlaybackSave(context))
        recentlySavedPlaybackContext = nil
        recentlySavedPosition = nil
        favoriteUndoCountdown = 0
        favoriteSaveResetTask?.cancel()
        showControlsTemporarily()
    }

    private static func normalizedMarkerPositions(_ positions: [Double]) -> [Double] {
        let sorted = positions
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()

        var normalized: [Double] = []
        normalized.reserveCapacity(sorted.count)

        for position in sorted {
            if let last = normalized.last, abs(last - position) < 2 {
                continue
            }
            normalized.append(position)
        }

        return normalized
    }
}

private struct HiddenPlaybackMarkerTrackView: View {
    let markerPositions: [Double]
    let duration: Double

    var body: some View {
        GeometryReader { geometry in
            if duration.isFinite, duration > 0 {
                ForEach(Array(normalizedFractions.enumerated()), id: \.offset) { _, fraction in
                    Capsule(style: .continuous)
                        .fill(Color.pink.opacity(0.95))
                        .frame(width: 3, height: 10)
                        .shadow(color: Color.black.opacity(0.32), radius: 2, y: 1)
                        .position(
                            x: max(1.5, min(geometry.size.width - 1.5, geometry.size.width * fraction)),
                            y: geometry.size.height / 2
                        )
                }
            }
        }
    }

    private var normalizedFractions: [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        return markerPositions.compactMap { position in
            guard position.isFinite, position >= 0 else { return nil }
            return min(max(position / duration, 0), 1)
        }
    }
}

private final class HiddenInAppWebViewState: ObservableObject {
    @Published var progress: Double = 0
    @Published var isLoading = true
    @Published var pageTitle = ""
    @Published var currentURL: URL?
    @Published var reloadToken = UUID()
}

private struct HiddenInAppWebPageView: View {
    let item: HiddenInAppWebPageItem

    @Environment(\.dismiss) private var dismiss
    @StateObject private var webState = HiddenInAppWebViewState()

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            HiddenInAppWebBrowserView(url: item.url, state: webState)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.82), Color.black.opacity(0.2), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 136)
                .overlay(alignment: .top) {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.14), in: Circle())
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text(webState.pageTitle.nonEmpty ?? webState.currentURL?.host ?? item.url.host ?? item.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                webState.reloadToken = UUID()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.14), in: Circle())
                            }
                            .buttonStyle(.plain)

                            Link(destination: webState.currentURL ?? item.url) {
                                Image(systemName: "safari")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.14), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                        if webState.isLoading {
                            ProgressView(value: webState.progress)
                                .tint(.white)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}

private struct HiddenInAppWebBrowserView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: HiddenInAppWebViewState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = HiddenJavDBAPI.userAgent
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.attachObservers(to: webView)
        context.coordinator.load(url: url, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURLString != url.absoluteString {
            context.coordinator.load(url: url, in: webView)
        }

        if context.coordinator.reloadToken != state.reloadToken {
            context.coordinator.reloadToken = state.reloadToken
            webView.reload()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: HiddenInAppWebViewState
        var loadedURLString: String?
        var reloadToken = UUID()
        private var progressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?

        init(state: HiddenInAppWebViewState) {
            self.state = state
        }

        func attachObservers(to webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.state.progress = webView.estimatedProgress
                }
            }
            titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.state.pageTitle = webView.title ?? ""
                }
            }
            urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.state.currentURL = webView.url
                }
            }
        }

        func load(url: URL, in webView: WKWebView) {
            loadedURLString = url.absoluteString
            state.isLoading = true
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue(HiddenJavDBAPI.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
            webView.load(request)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.isLoading = false
            state.progress = 1
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
        }
    }
}

private struct HiddenAVPlayerContainerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
        controller.updatesNowPlayingInfoCenter = false
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

struct HiddenJavDBImagePreviewView: View {
    let imageURLs: [URL]

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    init(imageURLs: [URL], initialIndex: Int) {
        self.imageURLs = imageURLs
        let safeIndex = min(max(initialIndex, 0), max(imageURLs.count - 1, 0))
        _currentIndex = State(initialValue: safeIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if imageURLs.isEmpty {
                Text("没有可显示的图片")
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, imageURL in
                        GeometryReader { proxy in
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case let .success(image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                case .empty:
                                    ProgressView()
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                case .failure:
                                    VStack(spacing: 10) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 24, weight: .semibold))
                                        Text("图片加载失败")
                                    }
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                Spacer()

                if !imageURLs.isEmpty {
                    Text("\(currentIndex + 1) / \(imageURLs.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 24)
                }
            }
        }
    }
}
