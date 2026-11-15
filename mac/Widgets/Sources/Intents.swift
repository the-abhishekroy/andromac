import AppIntents

struct ToggleConnectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Andromac connection"
    func perform() async throws -> some IntentResult { sendCommand("toggleConnection"); return .result() }
}

struct OpenPhoneIntent: AppIntent {
    static var title: LocalizedStringResource = "View phone"
    func perform() async throws -> some IntentResult { sendCommand("openPhone"); return .result() }
}

@available(macOS 26.0, *)
struct SetConnectionIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Andromac connection"
    @Parameter(title: "Connection") var value: Bool
    func perform() async throws -> some IntentResult { sendCommand(value ? "connectionOn" : "connectionOff"); return .result() }
}
