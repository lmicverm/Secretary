import Foundation

/// Geometry for the Mac document detail split (metadata vs preview).
/// Persisted as a meta-column width in `UserDefaults` via ``metaWidthDefaultsKey``.
public enum DetailSplitLayout {
    public static let metaMinWidth: Double = 280
    public static let previewMinWidth: Double = 360
    public static let dividerHitWidth: Double = 8
    public static let defaultMetaWidth: Double = 340
    public static let metaWidthDefaultsKey = "secretary.detailMetaWidth"

    public static var minimumSplitWidth: Double {
        metaMinWidth + previewMinWidth + dividerHitWidth
    }

    public static func canSplit(detailWidth: Double) -> Bool {
        detailWidth >= minimumSplitWidth
    }

    /// Clamp a proposed metadata column width so both panes keep their minima.
    /// When the pane is too narrow to split, returns a best-effort value without crashing.
    public static func clampedMetaWidth(_ proposed: Double, detailWidth: Double) -> Double {
        let maxMeta = detailWidth - previewMinWidth - dividerHitWidth
        guard maxMeta >= metaMinWidth else {
            return min(max(proposed, 0), max(detailWidth, 0))
        }
        return min(max(proposed, metaMinWidth), maxMeta)
    }
}
