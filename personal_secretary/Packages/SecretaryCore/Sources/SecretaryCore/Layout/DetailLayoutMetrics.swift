import Foundation

/// Sizing for the document detail pane. Shared so Mac and iOS stay consistent
/// and the math can be unit-tested without AppKit.
public struct DetailLayoutMetrics: Equatable, Sendable {
    public var contentWidth: CGFloat
    public var previewMinHeight: CGFloat
    public var previewMaxHeight: CGFloat
    public var usesSideColumn: Bool
    public var sideColumnWidth: CGFloat

    public static let macContentMax: CGFloat = 1280
    public static let iosContentMax: CGFloat = 680
    public static let contentWidthFraction: CGFloat = 0.96

    /// Remaining detail width at which Mac switches to preview + side metadata.
    public static let macWideBreakpoint: CGFloat = 800

    public static let macPreviewMin: CGFloat = 360
    public static let macPreviewFraction: CGFloat = 0.52
    public static let macStackedPreviewCapFraction: CGFloat = 0.62
    public static let macWidePreviewCapFraction: CGFloat = 0.82

    public static let iosPreviewMin: CGFloat = 220
    public static let iosPreviewMax: CGFloat = 320

    public static let macSideColumnMin: CGFloat = 300
    public static let macSideColumnMax: CGFloat = 400
    public static let macSideColumnFraction: CGFloat = 0.32

    public static let macSidebarMax: CGFloat = 300
    public static let iosSidebarMax: CGFloat = 260
    public static let macListMax: CGFloat = 460
    public static let iosListMax: CGFloat = 400

    public init(
        contentWidth: CGFloat,
        previewMinHeight: CGFloat,
        previewMaxHeight: CGFloat,
        usesSideColumn: Bool,
        sideColumnWidth: CGFloat
    ) {
        self.contentWidth = contentWidth
        self.previewMinHeight = previewMinHeight
        self.previewMaxHeight = previewMaxHeight
        self.usesSideColumn = usesSideColumn
        self.sideColumnWidth = sideColumnWidth
    }

    public static func resolve(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        isMac: Bool
    ) -> DetailLayoutMetrics {
        let width = max(0, availableWidth)
        let height = max(0, availableHeight)

        if isMac {
            let contentWidth = min(macContentMax, width * contentWidthFraction)
            let usesSide = width >= macWideBreakpoint
            let sideWidth = usesSide
                ? min(macSideColumnMax, max(macSideColumnMin, width * macSideColumnFraction))
                : 0
            let previewMin = max(macPreviewMin, height * macPreviewFraction)
            let capFraction = usesSide ? macWidePreviewCapFraction : macStackedPreviewCapFraction
            let previewMax = max(previewMin, height * capFraction)
            return DetailLayoutMetrics(
                contentWidth: contentWidth,
                previewMinHeight: previewMin,
                previewMaxHeight: previewMax,
                usesSideColumn: usesSide,
                sideColumnWidth: sideWidth
            )
        }

        return DetailLayoutMetrics(
            contentWidth: min(iosContentMax, width),
            previewMinHeight: iosPreviewMin,
            previewMaxHeight: iosPreviewMax,
            usesSideColumn: false,
            sideColumnWidth: 0
        )
    }
}
