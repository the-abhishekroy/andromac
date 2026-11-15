import SwiftUI

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String, symbol: String, hint: String
    var enabled = true
    var destructive = false
    let run: () -> Void
    init(title: String, symbol: String, hint: String, enabled: Bool = true, destructive: Bool = false, run: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.hint = hint; self.enabled = enabled; self.destructive = destructive; self.run = run
    }
}

/// Cmd+K quick actions: type to filter, arrows to move, Return to run, Escape to close.
struct CommandPalette: View {
    let commands: [PaletteCommand]
    let close: () -> Void
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var results: [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? commands : commands.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.hint.localizedCaseInsensitiveContains(q) }
    }

    private func run(_ c: PaletteCommand) {
        guard c.enabled else { return }
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { c.run() }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Brand.dim).accessibilityHidden(true)
                TextField("Type a command", text: $query).textFieldStyle(.plain).font(.title3)
                    .focused($focused)
                    .accessibilityLabel("Search quick actions")
                    .onSubmit { if results.indices.contains(index) { run(results[index]) } }
                    .onKeyPress(.downArrow) { index = min(index + 1, max(results.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
            }
            .padding(.horizontal, 16).frame(height: 56)
            Rectangle().fill(Brand.border).frame(height: 1)
            if results.isEmpty {
                Text("No matching actions").font(.callout).foregroundStyle(Brand.dim).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, c in row(c, selected: i == index) }
                }
                .padding(8)
            }
            Spacer(minLength: 0)
            Rectangle().fill(Brand.border).frame(height: 1)
            HStack(spacing: 16) {
                hintKey("\u{2191}\u{2193}", "move"); hintKey("\u{21A9}", "run"); hintKey("esc", "close")
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 36)
        }
        .frame(width: 480, height: 400)
        .background(Brand.surface)
        .preferredColorScheme(.dark)
        .tint(Brand.accent)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in index = 0 }
        .animation(Motion.fast(reduce), value: index)
    }

    private func hintKey(_ k: String, _ t: String) -> some View {
        HStack(spacing: 6) { Text(k).font(.footnote.weight(.semibold)); Text(t).font(.footnote).foregroundStyle(Brand.dim) }
            .accessibilityHidden(true)
    }

    private func row(_ c: PaletteCommand, selected: Bool) -> some View {
        Button { run(c) } label: {
            HStack(spacing: 12) {
                IconBadge(symbol: c.symbol, tint: c.destructive ? Brand.danger : Brand.accent, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.title).font(.body.weight(.medium)).foregroundStyle(c.destructive ? Brand.danger : .primary)
                    Text(c.hint).font(.footnote).foregroundStyle(Brand.dim)
                }
                Spacer()
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(selected ? Brand.surfaceRaised : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(c.enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.title).accessibilityHint(c.hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
