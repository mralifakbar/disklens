import SwiftUI

struct LegendItem: View {
    let color: Color
    let title: String
    var hatched = false

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(color.opacity(hatched ? 0.35 : 0.9))
                .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(color, lineWidth: hatched ? 1 : 0))
                .frame(width: 9, height: 9)
            Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }
}

struct Checkbox: View {
    let on: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(on ? Color.primary : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(on ? 0 : 0.3), lineWidth: 1.2))
            .overlay {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.card)
                }
            }
            .frame(width: 17, height: 17)
            .animation(.easeOut(duration: 0.12), value: on)
    }
}

struct PillButton: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(prominent ? Color.card : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(prominent ? Color.primary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Color.primary.opacity(0.18))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message).font(.system(size: 12.5))
            if let title = toast.actionTitle, let action = toast.action {
                Button(title, action: action)
                    .buttonStyle(PillButton(prominent: true))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hairline))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }
}
