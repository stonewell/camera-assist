import SwiftUI
import ComposeKit

@main
struct ReviewApp: App {
    @StateObject private var coordinator = PhotoReviewCoordinator()

    var body: some Scene {
        WindowGroup {
            PhotoReviewWorkspaceView(coordinator: coordinator)
        }
    }
}

/// Main workspace view for photo review, culling, and non-destructive auto-fixing.
public struct PhotoReviewWorkspaceView: View {
    @ObservedObject public var coordinator: PhotoReviewCoordinator
    @State private var filterMode: PhotoFilterMode = .all

    public init(coordinator: PhotoReviewCoordinator) {
        self.coordinator = coordinator
    }

    public enum PhotoFilterMode: String, CaseIterable, Identifiable {
        case all = "全部"
        case fixable = "待拯救"
        case good = "优秀"
        case culled = "已剔除"

        public var id: String { rawValue }
    }

    private var filteredPhotos: [ReviewPhotoViewModel] {
        switch filterMode {
        case .all:
            return coordinator.photos
        case .fixable:
            return coordinator.photos.filter { $0.isFixable && !$0.isCulled }
        case .good:
            return coordinator.photos.filter { $0.isGood && !$0.isCulled }
        case .culled:
            return coordinator.photos.filter { $0.isCulled }
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Trip Summary Metrics Banner
                summaryHeaderView
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.14))

                // Filter Picker
                Picker("Filter", selection: $filterMode) {
                    ForEach(PhotoFilterMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Virtualized Photo Grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 8)], spacing: 8) {
                        ForEach(filteredPhotos) { photo in
                            PhotoThumbnailCard(
                                photo: photo,
                                onToggleCull: { coordinator.toggleCull(for: photo.id) },
                                onApplyFix: { coordinator.previewAutoFix(for: photo.id) }
                            )
                        }
                    }
                    .padding(12)
                }

                // Batch Actions Toolbar
                bottomToolbarView
            }
            .navigationTitle("相册审片与废片拯救")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var summaryHeaderView: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("相片总数")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(coordinator.tripSummary.totalPhotos)")
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("平均评分")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f", coordinator.tripSummary.averageScore))
                    .font(.headline)
                    .foregroundColor(.yellow)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("待拯救废片")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(coordinator.tripSummary.fixablePhotos)")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("已剔除")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(coordinator.tripSummary.culledPhotos)")
                    .font(.headline)
                    .foregroundColor(.red)
            }
            Spacer()
        }
    }

    private var bottomToolbarView: some View {
        HStack(spacing: 16) {
            Button(action: { coordinator.batchApplyAllAutoFixes() }) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                    Text("一键拯救所有废片")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.yellow)
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.14))
    }
}

/// Thumbnail card displaying photo status, score, cull toggle, and auto-fix action.
public struct PhotoThumbnailCard: View {
    public let photo: ReviewPhotoViewModel
    public let onToggleCull: () -> Void
    public let onApplyFix: () -> Void

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(photo.isCulled ? Color.gray.opacity(0.3) : Color.secondary.opacity(0.22))
                .aspectRatio(1.0, contentMode: .fit)
                .overlay(
                    VStack(spacing: 4) {
                        Text(photo.filename)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(photo.score) 分")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(photo.score >= 80 ? .green : .orange)
                        if photo.isFixable {
                            Button(action: onApplyFix) {
                                Text("废片拯救")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow.opacity(0.9))
                                    .foregroundColor(.black)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                )

            Button(action: onToggleCull) {
                Image(systemName: photo.isCulled ? "trash.fill" : "trash")
                    .font(.system(size: 12))
                    .foregroundColor(photo.isCulled ? .red : .secondary)
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(photo.activeAdjustment != nil ? Color.green : Color.clear, lineWidth: 2)
        )
    }
}
