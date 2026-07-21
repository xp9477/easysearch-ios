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
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                ESStatusBanner(
                    title: "私密空间已解锁",
                    message: "离开工作台或退到后台后会自动锁定。",
                    systemImage: "lock.shield",
                    tone: .accent
                )

                VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                    ESSectionHeader(title: "入口")

                    NavigationLink(value: HiddenSpaceRoute.fourKHD) {
                        hiddenEntryCard(
                            title: "4khd",
                            summary: "随机封面、专辑全图与喜欢列表",
                            systemImage: "photo.stack",
                            color: .blue,
                            badges: [
                                settings.fourKHDRandomMode.title,
                                "\(fourKHDFavoritesCount) 喜欢"
                            ]
                        )
                    }
                    .buttonStyle(ESCardButtonStyle())

                    NavigationLink(value: HiddenSpaceRoute.javDB) {
                        hiddenEntryCard(
                            title: "javdb",
                            summary: "随机影片、喜欢列表与详情播放",
                            systemImage: "film.stack",
                            color: .purple,
                            badges: [
                                settings.javDBRandomMode.title,
                                "\(javDBFavoritesCount) 喜欢",
                                "\(javDBPlaybackCount) 点位"
                            ],
                            footer: "MissAV：\(HiddenMissAVDomainConfiguration.resolvedHost(from: settings.missAVDomain))"
                        )
                    }
                    .buttonStyle(ESCardButtonStyle())
                }
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.lg)
        }
        .esScreenBackground()
        .navigationTitle("隐藏空间")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: HiddenSpaceRoute.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("隐藏空间设置")
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

    private func hiddenEntryCard(
        title: String,
        summary: String,
        systemImage: String,
        color: Color,
        badges: [String],
        footer: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack(spacing: ESUI.Space.sm) {
                ESFeatureIcon(systemName: systemImage, color: color, size: 44)

                VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: ESUI.Space.xs)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            HStack(spacing: ESUI.Space.xs) {
                ForEach(badges, id: \.self) { badge in
                    ESStatusBadge(text: badge, tone: .accent)
                }
            }

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
