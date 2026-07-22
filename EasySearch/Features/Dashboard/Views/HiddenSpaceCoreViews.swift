import SwiftUI

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
                ESModuleHero(
                    title: "隐藏空间",
                    subtitle: "离开工作台或退后台将自动锁定",
                    featureID: "hidden-space",
                    systemImage: "lock.shield"
                )

                ESStatusBanner(
                    title: "已解锁",
                    message: "内容仅在本页停留期间可见。",
                    systemImage: "lock.open",
                    tone: .accent
                )

                VStack(alignment: .leading, spacing: ESUI.Space.sm) {
                    ESSectionHeader(title: "入口")

                    NavigationLink(value: HiddenSpaceRoute.fourKHD) {
                        hiddenEntryCard(
                            title: "4khd",
                            summary: "随机封面、专辑与喜欢",
                            systemImage: "photo.stack",
                            featureID: "image-translate",
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
                            summary: "随机影片、喜欢与播放",
                            systemImage: "film.stack",
                            featureID: "hidden-space",
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
        featureID: String,
        badges: [String],
        footer: String? = nil
    ) -> some View {
        let pair = ESUI.ModuleAccent.pair(for: featureID)
        return VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack(spacing: ESUI.Space.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: ESUI.Space.xxs) {
                    Text(title)
                        .font(.body.weight(.bold))
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
