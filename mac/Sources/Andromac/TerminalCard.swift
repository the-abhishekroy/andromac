import SwiftUI
import AppKit

/// Plain-language terminal help: two short commands, with the raw ports tucked under "Advanced".
struct TerminalCard: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var copied: String?
    @State private var advanced = false

    var body: some View {
        Card(title: "Terminal", subtitle: "Open a terminal on one device from the other, with one short command. It travels over Andromac's private network, so it works from any Wi-Fi or mobile data.") {
            ToggleRow(symbol: "terminal.fill", title: "Allow terminal access",
                      detail: "Lets your own devices open a terminal on each other. On the Mac, turn on Remote Login in System Settings \u{203A} General \u{203A} Sharing.",
                      isOn: $m.terminalAccess)
            Divider().overlay(Brand.border)
            shortcut(title: "From your phone to this Mac", command: "ssh m5",
                     detail: "Type it in Termux on your phone to reach this Mac.")
            shortcut(title: "From this Mac to your phone", command: "ssh f14",
                     detail: "Type it in Terminal on this Mac to reach your phone.")
            DisclosureGroup(isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Full commands, if the shortcuts are not set up yet.").font(.callout).foregroundStyle(Brand.dim)
                    raw("Phone to Mac, through port 2222", "ssh -p 2222 \(NSUserName())@127.0.0.1")
                    raw("Mac to phone, through port 2223", "ssh -p 2223 127.0.0.1")
                }
                .padding(.top, 10)
            } label: {
                Text("Advanced").font(.callout.weight(.semibold))
            }
            .animation(Motion.normal(reduce), value: advanced)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        withAnimation(Motion.fast(reduce)) { copied = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == text { withAnimation(Motion.fast(reduce)) { copied = nil } } }
    }

    private func copyButton(_ text: String, label: String) -> some View {
        Button { copy(text) } label: {
            Label(copied == text ? "Copied" : "Copy", systemImage: copied == text ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copied == text ? Brand.accent : Color.primary)
        }
        .buttonStyle(.brandCompact)
        .accessibilityLabel("Copy \(label)")
    }

    private func shortcut(title: String, command: String, detail: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(Brand.dim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(command).font(.body.monospaced()).foregroundStyle(Brand.accent)
                .padding(.horizontal, 12).frame(minHeight: 36)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Brand.border))
                .textSelection(.enabled)
            copyButton(command, label: command)
        }
        .accessibilityElement(children: .contain)
    }

    private func raw(_ title: String, _ command: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.medium))
                Text(command).font(.callout.monospaced()).foregroundStyle(Brand.dim).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            copyButton(command, label: command)
        }
    }
}
