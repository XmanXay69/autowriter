//
//  Theme.swift
//  AutoWriter's look, matching Window Watcher: dark gray background,
//  slightly lighter rounded "cards", small gray captions, one accent color
//  (your macOS accent color, System Settings → Appearance), and a colored
//  status "pill". The colors are the dark-mode colors from Window Watcher's theme.py.
//

import SwiftUI

enum Theme {
    static let background = Color(hex: 0x1C1C1E)
    static let card = Color(hex: 0x262628)
    static let border = Color.white.opacity(0.07)
    static let field = Color(hex: 0x1C1C1E)
    static let button = Color(hex: 0x3A3A3C)
    static let buttonHover = Color(hex: 0x48484A)
    static let text = Color(hex: 0xF5F5F7)
    static let secondary = Color(hex: 0x98989D)
    static let red = Color(hex: 0xFF453A)
    static let accent = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.16)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// A rounded panel that groups related things.
struct Card<Content: View>: View {
    var padding = EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
    }
}

/// A small gray heading like "DOCUMENT" at the top of a card.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.secondary)
    }
}

/// "●  Typing": accent-tinted while something is happening, gray otherwise.
struct StatusPill: View {
    let text: String
    let active: Bool

    var body: some View {
        Text("●  \(text)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? Theme.accent : Theme.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 3)
            .background(active ? Theme.accentSoft : Theme.button, in: Capsule())
            .monospacedDigit()
    }
}

/// Buttons in Window Watcher's style.
struct AWButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, link, big }
    var kind: Kind = .normal

    func makeBody(configuration: Configuration) -> some View {
        AWButton(configuration: configuration, kind: kind)
    }

    private struct AWButton: View {
        let configuration: Configuration
        let kind: Kind
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .opacity(configuration.isPressed ? 0.8 : 1)
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
        }

        @ViewBuilder private var label: some View {
            switch kind {
            case .normal:
                configuration.label
                    .font(.system(size: 13))
                    .foregroundStyle(isEnabled ? Theme.text : Theme.secondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(hovering && isEnabled ? Theme.buttonHover : Theme.button, in: RoundedRectangle(cornerRadius: 8))
            case .primary:
                configuration.label
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(isEnabled ? (hovering ? 0.88 : 1) : 0.35), in: RoundedRectangle(cornerRadius: 8))
            case .big:
                configuration.label
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Theme.accent.opacity(isEnabled ? (hovering ? 0.88 : 1) : 0.35), in: RoundedRectangle(cornerRadius: 11))
            case .link:
                configuration.label
                    .font(.system(size: 12))
                    .foregroundStyle(hovering && isEnabled ? Theme.accent : Theme.secondary)
            }
        }
    }
}

extension ButtonStyle where Self == AWButtonStyle {
    static var aw: AWButtonStyle { AWButtonStyle() }
    static var awPrimary: AWButtonStyle { AWButtonStyle(kind: .primary) }
    static var awBig: AWButtonStyle { AWButtonStyle(kind: .big) }
    static var awLink: AWButtonStyle { AWButtonStyle(kind: .link) }
}
