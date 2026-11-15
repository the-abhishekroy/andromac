import Foundation
import Combine
import WidgetKit

/// Publishes live state to ~/.andromac/widget-status.json for the WidgetKit extension and executes
/// commands the widgets send back (DistributedNotificationCenter "app.andromac.widget.command").
final class WidgetBridge {
    static let commandName = Notification.Name("app.andromac.widget.command")
    private unowned let model: AppModel
    private var bag = Set<AnyCancellable>()
    private var last = Data()
    private var lastChange = Date()
    private let url: URL

    init(model: AppModel) {
        self.model = model
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".andromac")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("widget-status.json")
        model.objectWillChange.debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.publish() }.store(in: &bag)
        DistributedNotificationCenter.default().addObserver(forName: Self.commandName, object: nil, queue: .main) { [weak self] n in
            let cmd = (n.object as? String) ?? ""
            self?.run(cmd)
        }
        publish()
    }

    private func run(_ cmd: String) {
        switch cmd {
        case "toggleConnection": model.connectionEnabled.toggle()
        case "connectionOn": model.connectionEnabled = true
        case "connectionOff": model.connectionEnabled = false
        case "openPhone": model.requestPhoneScreen()
        default: break
        }
    }

    private func publish() {
        let clip = model.clipboardHistory.first
        var o: [String: Any] = [
            "enabled": model.connectionEnabled, "connected": model.connected, "charging": model.charging,
            "clip": clip.map { $0.displayText } ?? "",
        ]
        if let n = model.phoneName { o["phoneName"] = n }
        if let b = model.battery { o["battery"] = b }
        guard let core = try? JSONSerialization.data(withJSONObject: o, options: .sortedKeys), core != last else { return }
        last = core; lastChange = Date()
        o["updated"] = lastChange.timeIntervalSince1970
        if let d = try? JSONSerialization.data(withJSONObject: o, options: .sortedKeys) { try? d.write(to: url, options: .atomic) }
        WidgetCenter.shared.reloadAllTimelines()
        if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
    }
}
