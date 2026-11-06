import SwiftUI

/// A card's title above it, Panefold-style, with optional controls on the trailing side.
struct CardHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing
        }
        .frame(minHeight: 44)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct LegendItem: View {
    let color: Color
    let title: String
    var hatched = false

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(hatched ? 0.35 : 0.85))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color, lineWidth: hatched ? 1 : 0))
                .frame(width: 10, height: 10)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct Checkbox: View {
    let on: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(on ? Color.accentColor : Color.primary.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(on ? 0 : 0.25), lineWidth: 1))
            .overlay {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
            .animation(.easeOut(duration: 0.12), value: on)
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message).font(.callout)
            if let title = toast.actionTitle, let action = toast.action {
                Button(title, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }
}
