import SwiftUI

// MARK: - Liquid Glass Design Notes
// ──────────────────────────────────
//
// Apple's Liquid Glass (iOS 26) is NOT glassmorphism:
//
// 1. REFRACTION (lensing): Edges warp background content via a convex
//    squircle bevel profile. The system uses Metal shaders to displace
//    pixels at the glass boundary, creating a real "looking through
//    curved glass" effect. This is the #1 visual differentiator.
//
// 2. SPECULAR HIGHLIGHTS: A bright rim light appears along the top edge,
//    its intensity calculated from the surface normal vs. light direction
//    dot product. It varies naturally around the shape's contour.
//
// 3. TRANSLUCENCY: Background shows through with depth — not just
//    blur + transparency, but adaptive brightness/saturation adjustment.
//
// 4. HIERARCHY: Glass is ONLY for the navigation/control layer.
//    Content (text, images, data) stays clean. Never glass-on-glass.
//
// 5. CONCENTRICITY: Nested rounded shapes maintain proportional radii
//    so inner corners nest smoothly within outer corners.
//
// 6. MORPHING: GlassEffectContainer groups related controls.
//    Within the container's spacing threshold, separate glass elements
//    merge into one continuous shape during transitions.
//
// 7. VARIANTS:
//    - .regular: Default. Adaptive tinting, medium translucency.
//    - .clear: High transparency, no adaptive tinting. For media BGs.
//    - .identity: Disable glass (useful for opt-out in containers).
//
// 8. MODIFIERS:
//    - .tint(.color): Semantic color overlay (e.g. indigo for active state)
//    - .interactive(): Press-scale behavior (shrinks slightly on tap)
//
// ──────────────────────────────────

// MARK: - Concentric Radius Helper
// Apple's concentricity principle: inner corner radius = outer radius - padding.
// This ensures nested rounded shapes look harmonious, not jarring.
struct ConcentricRadius {
    /// Calculate inner corner radius that nests concentrically within outer radius.
    /// Returns max(0, outerRadius - padding) so inner shapes always fit smoothly.
    static func inner(outerRadius: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, outerRadius - padding)
    }

    /// Standard iOS device corner radius for reference
    static let deviceCorner: CGFloat = 44

    /// Tab bar corner radius (concentric with device corners)
    static let tabBar: CGFloat = 36

    /// Standard card within a navigation stack
    static let card: CGFloat = 20

    /// Button/chip within a card
    static let chip: CGFloat = 16

    /// Small badge
    static let badge: CGFloat = 12
}

// MARK: - Scroll Offset Tracking
// Used to track scroll position for showing/hiding controls.
// In iOS 26, the tab bar shrinks automatically on scroll,
// but custom floating controls need manual tracking.
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Track scroll offset and report via preference key
    func trackScrollOffset() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ScrollOffsetKey.self,
                    value: geo.frame(in: .named("scroll")).minY
                )
            }
        )
    }
}

// MARK: - Compatibility Wrappers
// These wrappers allow the project to compile on earlier iOS versions
// with graceful degradation. On iOS 26+, they use real Liquid Glass.
// On earlier versions, they fall back to .ultraThinMaterial.

extension View {
    /// Apply glass effect with fallback for older iOS
    @ViewBuilder
    func adaptiveGlass(
        in shape: some Shape = Capsule(),
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                if interactive {
                    self.glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    self.glassEffect(.regular.tint(tint), in: shape)
                }
            } else {
                if interactive {
                    self.glassEffect(.regular.interactive(), in: shape)
                } else {
                    self.glassEffect(.regular, in: shape)
                }
            }
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .clipShape(shape)
        }
    }

    /// Clear glass variant for media backgrounds
    @ViewBuilder
    func clearGlass(in shape: some Shape = RoundedRectangle(cornerRadius: 20, style: .continuous)) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear, in: shape)
        } else {
            self
                .background(shape.fill(.thinMaterial))
                .clipShape(shape)
        }
    }
}

// MARK: - BookFormat Icon Helper
extension BookFormat {
    var iconName: String {
        switch self {
        case .epub: return "book"
        case .pdf: return "doc.text"
        case .mobi: return "iphone"
        }
    }

    var displayName: String {
        rawValue.uppercased()
    }
}
