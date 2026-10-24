// One compact notice: icon, title, message, optional action button and a close button.

import SwiftUI

struct NoticeBanner: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: () -> Void
    let dismissLabel: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.warning)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .pointerCursor()
            }
            IconButton(systemImage: "xmark", label: dismissLabel, size: 10, weight: .bold, frame: 18, action: onDismiss)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .card(cornerRadius: Theme.Radius.notice)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
