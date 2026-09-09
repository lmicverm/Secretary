import SecretaryCore
import SwiftUI

/// Quiet ink-on-paper look for a personal archive.
enum SecretaryTheme {
    // MARK: - Colors
    
    static let accent = Color(red: 0.12, green: 0.35, blue: 0.38)
    static let accentSoft = Color(red: 0.12, green: 0.35, blue: 0.38).opacity(0.10)
    static let accentMuted = Color(red: 0.12, green: 0.35, blue: 0.38).opacity(0.06)
    
    static let warn = Color(red: 0.72, green: 0.38, blue: 0.12)
    static let warnSoft = Color(red: 0.72, green: 0.38, blue: 0.12).opacity(0.08)
    
    static let success = Color(red: 0.22, green: 0.55, blue: 0.35)
    static let successSoft = Color(red: 0.22, green: 0.55, blue: 0.35).opacity(0.10)
    
    static let panel = Color.primary.opacity(0.025)
    static let panelHover = Color.primary.opacity(0.04)
    static let stroke = Color.primary.opacity(0.07)
    static let strokeSubtle = Color.primary.opacity(0.04)
    
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.primary.opacity(0.4)
    
    // MARK: - Radii
    
    static let radiusSmall: CGFloat = 6
    static let radius: CGFloat = 10
    static let radiusLarge: CGFloat = 14
    
    // MARK: - Spacing
    
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32
    
    static let sectionSpacing: CGFloat = 20
    static let pagePadding: CGFloat = 24
    static let panelPadding: CGFloat = 16
    
    // MARK: - Layout
    
    static let sidebarWidth: CGFloat = 220
    static let listWidth: CGFloat = 320
    /// Readable form width on iOS stacked detail.
    static let detailContentMax: CGFloat = 680
    #if os(macOS)
    /// When the detail pane is at least this wide, metadata sits left and preview fills the rest.
    static let detailSplitMinWidth = CGFloat(DetailSplitLayout.minimumSplitWidth)
    static let detailMetaMinWidth = CGFloat(DetailSplitLayout.metaMinWidth)
    static let detailPreviewMinWidth = CGFloat(DetailSplitLayout.previewMinWidth)
    static let previewMinHeight: CGFloat = 420
    static let previewIdealHeight: CGFloat = 520
    static let previewMaxHeight: CGFloat = 920
    static let previewHeightRatio: CGFloat = 0.55
    #else
    static let previewMinHeight: CGFloat = 220
    static let previewIdealHeight: CGFloat = 260
    static let previewMaxHeight: CGFloat = 320
    #endif
    static let windowMinWidth: CGFloat = 1100
    static let windowMinHeight: CGFloat = 640
    static let windowDefaultWidth: CGFloat = 1440
    static let windowDefaultHeight: CGFloat = 860

    #if os(macOS)
    static func previewHeight(forViewport viewportHeight: CGFloat) -> CGFloat {
        let proposed = viewportHeight * previewHeightRatio
        return min(previewMaxHeight, max(previewMinHeight, proposed))
    }
    #endif
}

// MARK: - Typography

extension SecretaryTheme {
    enum Typography {
        static let pageTitle = Font.title2.weight(.semibold)
        static let sectionTitle = Font.subheadline.weight(.semibold)
        static let sectionHeader = Font.caption.weight(.medium)
        
        static let bodyPrimary = Font.body
        static let bodyMedium = Font.body.weight(.medium)
        static let bodySecondary = Font.subheadline
        
        static let caption = Font.caption
        static let captionMedium = Font.caption.weight(.medium)
        static let captionBold = Font.caption.weight(.semibold)
        
        static let metadata = Font.caption2
        static let metadataMono = Font.caption2.monospacedDigit()
    }
}

// MARK: - View Modifiers

extension View {
    func sectionHeaderStyle() -> some View {
        self
            .font(SecretaryTheme.Typography.sectionHeader)
            .foregroundStyle(SecretaryTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.3)
    }
    
    func rowLabelStyle() -> some View {
        self
            .font(SecretaryTheme.Typography.bodyMedium)
            .foregroundStyle(SecretaryTheme.textPrimary)
    }
    
    func metadataStyle() -> some View {
        self
            .font(SecretaryTheme.Typography.caption)
            .foregroundStyle(SecretaryTheme.textSecondary)
    }
}

struct SecretaryPanel<Content: View>: View {
    var tint: Color = SecretaryTheme.panel
    var stroke: Color = SecretaryTheme.strokeSubtle
    var padding: CGFloat = SecretaryTheme.panelPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SecretaryTheme.radius, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SecretaryTheme.radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 0.5)
            )
    }
}

/// Centered readable column for iOS (and any stacked form that should not stretch edge-to-edge).
struct DetailPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content()
                    .frame(maxWidth: SecretaryTheme.detailContentMax, alignment: .leading)
                    .padding(.horizontal, SecretaryTheme.pagePadding)
                    .padding(.vertical, SecretaryTheme.spacingXL)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Consistent empty state display across the app.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var description: String? = nil
    
    var body: some View {
        VStack(spacing: SecretaryTheme.spacingMD) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(SecretaryTheme.textTertiary)
            
            Text(title)
                .font(SecretaryTheme.Typography.bodyMedium)
                .foregroundStyle(SecretaryTheme.textSecondary)
            
            if let description {
                Text(description)
                    .font(SecretaryTheme.Typography.caption)
                    .foregroundStyle(SecretaryTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SecretaryTheme.spacingXL)
    }
}

/// Status banner for success/error messages in forms.
struct StatusBanner: View {
    enum Style {
        case success, error, info
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
        
        var tint: Color {
            switch self {
            case .success: return SecretaryTheme.success
            case .error: return Color.red
            case .info: return SecretaryTheme.accent
            }
        }
        
        var background: Color {
            switch self {
            case .success: return SecretaryTheme.successSoft
            case .error: return Color.red.opacity(0.08)
            case .info: return SecretaryTheme.accentSoft
            }
        }
    }
    
    let message: String
    let style: Style
    
    var body: some View {
        HStack(spacing: SecretaryTheme.spacingSM) {
            Image(systemName: style.icon)
                .foregroundStyle(style.tint)
            Text(message)
                .font(SecretaryTheme.Typography.caption)
                .foregroundStyle(SecretaryTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SecretaryTheme.spacingMD)
        .padding(.vertical, SecretaryTheme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: SecretaryTheme.radiusSmall, style: .continuous)
                .fill(style.background)
        )
    }
}
