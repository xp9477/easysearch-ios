import SwiftUI

enum HiddenSpaceRoute: Hashable {
    case javDBSettings
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
    @State private var fourKHDFavoritesCount = 0
    @State private var javDBFavoritesCount = 0
    @State private var javDBPlaybackCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ESUI.sectionSpacing) {
                NavigationLink(value: HiddenSpaceRoute.fourKHD) {
                    hiddenEntryCard(
                        title: "4khd",
                        summary: "随机封面、专辑与喜欢",
                        systemImage: "photo.stack",
                        featureID: "hidden-space",
                        badges: [
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
                            "\(javDBFavoritesCount) 喜欢",
                            "\(javDBPlaybackCount) 点位"
                        ]
                    )
                }
                .buttonStyle(ESCardButtonStyle())
            }
            .padding(.horizontal, ESUI.screenHorizontalPadding)
            .padding(.top, ESUI.Space.md)
            .padding(.bottom, ESUI.Space.lg)
        }
        .esScreenBackground()
        .navigationTitle("隐藏空间")
        .navigationBarTitleDisplayMode(.inline)
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
        let accent = ESUI.moduleColor(for: featureID)
        return VStack(alignment: .leading, spacing: ESUI.Space.sm) {
            HStack(spacing: ESUI.Space.sm) {
                ESFeatureIcon(systemName: systemImage, color: accent, size: 44)

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
        fourKHDFavoritesCount = Hidden4KHDLocalStore.loadFavoriteAlbums().count + Hidden4KHDLocalStore.loadFavoriteImages().count
        javDBFavoritesCount = HiddenJavDBLocalStore.loadFavoriteMovies().count
        javDBPlaybackCount = HiddenJavDBLocalStore.loadFavoritePlaybacks().count
    }
}
