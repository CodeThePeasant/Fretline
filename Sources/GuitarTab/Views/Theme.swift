import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.065, blue: 0.07)
    static let surface = Color(red: 0.085, green: 0.099, blue: 0.103)
    static let elevated = Color(red: 0.12, green: 0.135, blue: 0.14)
    static let accent = Color(red: 0.73, green: 0.91, blue: 0.58)
    static let muted = Color(red: 0.52, green: 0.57, blue: 0.57)
    static let line = Color.white.opacity(0.09)
    static let orange = Color(red: 0.96, green: 0.69, blue: 0.40)
}

struct ActionStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 15).padding(.vertical, 11)
            .foregroundStyle(primary ? Theme.background : Color.white.opacity(0.85))
            .background(primary ? Theme.accent : Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct SectionLabel: View {
    let title: String
    var body: some View { Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Theme.muted) }
}

func clockText(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
}
