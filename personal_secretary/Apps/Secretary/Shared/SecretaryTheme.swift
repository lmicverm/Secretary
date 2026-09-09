import SwiftUI

/// Quiet ink-on-paper look for a personal archive.
enum SecretaryTheme {
    static let accent = Color(red: 0.12, green: 0.35, blue: 0.38)
    static let accentSoft = Color(red: 0.12, green: 0.35, blue: 0.38).opacity(0.12)
    static let warn = Color(red: 0.72, green: 0.38, blue: 0.12)
    static let warnSoft = Color(red: 0.72, green: 0.38, blue: 0.12).opacity(0.10)
    static let panel = Color.primary.opacity(0.035)
    static let stroke = Color.primary.opacity(0.09)
    static let radius: CGFloat = 12

    static let sidebarWidth: CGFloat = 220
    static let listWidth: CGFloat = 320
    static let detailContentMax: CGFloat = 680
    static let windowMinWidth: CGFloat = 960
    static let windowMinHeight: CGFloat = 600
    static let windowDefaultWidth: CGFloat = 1180
    static let windowDefaultHeight: CGFloat = 740
    static let sectionSpacing: CGFloat = 16
    static let pagePadding: CGFloat = 24
}

struct SecretaryPanel<Content: View>: View {
    var tint: Color = SecretaryTheme.panel
    var stroke: Color = SecretaryTheme.stroke
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SecretaryTheme.radius, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SecretaryTheme.radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }
}

/// Keeps detail content readable instead of stretching edge-to-edge on wide screens.
struct DetailPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content()
                    .frame(maxWidth: SecretaryTheme.detailContentMax, alignment: .leading)
                    .padding(.horizontal, SecretaryTheme.pagePadding)
                    .padding(.vertical, SecretaryTheme.pagePadding)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
