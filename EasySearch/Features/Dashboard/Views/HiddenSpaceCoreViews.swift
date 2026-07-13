import SwiftUI
import WebKit
import AVKit
@preconcurrency import AVFoundation
import UIKit

enum HiddenSpaceRoute: Hashable {
    case settings
    case fourKHD
    case fourKHDFavorites
    case fourKHDFavoriteImages
    case fourKHDFavoriteAlbums
    case fourKHDAlbum(HiddenAlbum)
    case javDB
    case javDBFavorites
    case javDBMovie(HiddenJavDBMovie)
}

enum HiddenSpacePresentedModal: Hashable {
    case fourKHDFavoritesPreview(PreviewImage)
    case albumDetailPreview(albumID: String, preview: PreviewImage)
    case javDBFavoritesPlayer(HiddenSharedPlayerItem)
    case javDBMoviePreview(movieID: String, preview: HiddenJavDBPreviewImage)
    case javDBMoviePlayer(movieID: String, item: HiddenSharedPlayerItem)
    case javDBMovieWebPage(movieID: String, item: HiddenSharedWebPageItem)
}

@MainActor
final class HiddenSpacePresentationState: ObservableObject {
    @Published var modal: HiddenSpacePresentedModal?
}

struct HiddenSpaceView: View {
    @State private var settings = HiddenSpaceSettingsStore.shared.load()
    @State private var fourKHDFavoritesCount = 0
    @State private var javDBFavoritesCount = 0
    @State private var javDBPlaybackCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ESInfoBanner(
                    title: "私密入口已开启",
                    systemImage: "lock.shield",
                    tone: .accent
                )

                NavigationLink(value: HiddenSpaceRoute.fourKHD) {
                    fourKHDFeatureCard
                }
                .buttonStyle(ESCardButtonStyle())

                NavigationLink(value: HiddenSpaceRoute.javDB) {
                    javDBFeatureCard
                }
                .buttonStyle(ESCardButtonStyle())

            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, 14)
            .esBottomTabPadding()
        }
        .esScreenBackground()
        .navigationTitle("隐藏空间")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: HiddenSpaceRoute.settings) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .onAppear(perform: refreshSummary)
        .onReceive(NotificationCenter.default.publisher(for: .hiddenSpaceSettingsDidChange)) { _ in
            refreshSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshSummary()
        }
    }

    private var fourKHDFeatureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ESFeatureIcon(systemName: "photo.stack", color: .blue, size: 54)

                VStack(alignment: .leading, spacing: 6) {
                    Text("4khd")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("随机封面、album 全图、喜欢列表")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                ESStatusPill(text: settings.fourKHDRandomMode.title, tone: .accent)
                ESStatusPill(text: "\(fourKHDFavoritesCount) 喜欢", tone: fourKHDFavoritesCount > 0 ? .success : .neutral)
            }
        }
        .esCard()
    }

    private var javDBFeatureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ESFeatureIcon(systemName: "film.stack", color: .purple, size: 54)

                VStack(alignment: .leading, spacing: 6) {
                    Text("javdb")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("随机影片、喜欢影片、详情信息")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                ESStatusPill(text: settings.javDBRandomMode.title, tone: .accent)
                ESStatusPill(text: "\(javDBFavoritesCount) 喜欢", tone: javDBFavoritesCount > 0 ? .success : .neutral)
                ESStatusPill(text: "\(javDBPlaybackCount) 点位", tone: javDBPlaybackCount > 0 ? .success : .neutral)
            }

            Text("MissAV：\(HiddenMissAVDomainConfiguration.resolvedHost(from: settings.missAVDomain))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .esCard()
    }

    private func refreshSummary() {
        settings = HiddenSpaceSettingsStore.shared.load()
        fourKHDFavoritesCount = Hidden4KHDLocalStore.loadFavoriteAlbums().count + Hidden4KHDLocalStore.loadFavoriteImages().count
        javDBFavoritesCount = HiddenJavDBLocalStore.loadFavoriteMovies().count
        javDBPlaybackCount = HiddenJavDBLocalStore.loadFavoritePlaybacks().count
    }

}
