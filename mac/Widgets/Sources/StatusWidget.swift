import WidgetKit
import SwiftUI
import AppIntents

struct StatusEntry: TimelineEntry { let date: Date; let status: AndromacStatus }

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        var s = AndromacStatus(); s.enabled = true; s.connected = true; s.phoneName = "Pixel"; s.battery = 80; s.clip = "Copied text"; s.updated = Date()
        return StatusEntry(date: Date(), status: s)
    }
    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : StatusEntry(date: Date(), status: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        completion(Timeline(entries: [StatusEntry(date: Date(), status: .load())], policy: .after(Date().addingTimeInterval(900))))
    }
}

struct Dot: View {
    let on: Bool
    var body: some View { Circle().fill(on ? Flat.accent : Flat.dim).frame(width: 9, height: 9) }
}

struct StatusView: View {
    @Environment(\.widgetFamily) var family
    let e: StatusEntry
    var s: AndromacStatus { e.status }

    var header: some View {
        HStack(spacing: 6) {
            Dot(on: s.connected)
            Text(s.statusText).font(.system(size: 13, weight: .semibold)).foregroundStyle(s.connected ? Flat.accent : Flat.dim)
        }
    }
    var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Text(s.phoneName ?? "No phone").font(.system(size: 17, weight: .semibold)).foregroundStyle(Flat.text).lineLimit(1)
            if let b = s.battery {
                Text("\(b)%\(s.charging ? " charging" : "")").font(.system(size: 13)).foregroundStyle(Flat.dim)
            }
            if let u = s.updated {
                (Text("Synced ") + Text(u, style: .relative)).font(.system(size: 11)).foregroundStyle(Flat.dim).lineLimit(1)
            }
        }
    }
    func button(_ title: String, _ icon: String, _ intent: some AppIntent) -> some View {
        Button(intent: intent) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(Flat.accent)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Flat.accent.opacity(0.6), lineWidth: 1))
        }.buttonStyle(.plain)
    }
    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading) { info; Spacer(minLength: 0) }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        info
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            button(s.enabled ? "Turn off" : "Turn on", "power", ToggleConnectionIntent())
                            button("View phone", "iphone", OpenPhoneIntent())
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CLIPBOARD").font(.system(size: 10, weight: .semibold)).foregroundStyle(Flat.dim)
                        Text(s.clip.isEmpty ? "Nothing yet" : s.clip).font(.system(size: 13)).foregroundStyle(Flat.text).lineLimit(5)
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .containerBackground(Flat.bg, for: .widget)
    }
}

struct AndromacStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AndromacStatus", provider: StatusProvider()) { StatusView(e: $0) }
            .configurationDisplayName("Andromac")
            .description("Phone connection status, with quick controls.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
