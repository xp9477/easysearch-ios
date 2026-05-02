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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink(value: HiddenSpaceRoute.fourKHD) {
                    fourKHDFeatureCard
                }
                .buttonStyle(.plain)

                NavigationLink(value: HiddenSpaceRoute.javDB) {
                    javDBFeatureCard
                }
                .buttonStyle(.plain)

            }
            .padding(16)
            .padding(.bottom, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("隐藏空间")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: HiddenSpaceRoute.settings) {
                    Image(systemName: "gearshape")
                }
            }
        }
    }

    private var fourKHDFeatureCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 54, height: 54)
                Image(systemName: "photo.stack")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
            }

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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var javDBFeatureCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 54, height: 54)
                Image(systemName: "film.stack")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("javdb")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("随机影片、喜欢影片、详情信息（默认折叠）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

}
