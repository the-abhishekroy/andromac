import Foundation
import CryptoKit

// Fake phone: connects to the local daemon, sends an SMS with an OTP + a clipboard item,
// then replays an old seq and sends a frame with a wrong key. Run the daemon first.
let secretFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".andromac/secret")
let secret = try! Data(contentsOf: secretFile)

func key(_ s: Data) -> SymmetricKey {
    HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: s), salt: Data("andromac-v1".utf8),
                           info: Data("msg-key".utf8), outputByteCount: 32)
}
func frame(_ k: SymmetricKey, seq: Int, type: String, data: [String: Any]) -> Data {
    let env: [String: Any] = ["seq": seq, "type": type, "ts": 0, "data": data]
    return try! ChaChaPoly.seal(JSONSerialization.data(withJSONObject: env), using: k).combined
}

let k = key(secret)
let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:8765/")!)
task.resume()
func send(_ d: Data) { task.send(.data(d)) { if let e = $0 { print("send error: \(e)") } } }

send(frame(k, seq: 1, type: "hello", data: ["device": "TestPhone", "version": 1]))
send(frame(k, seq: 2, type: "sms", data: ["from": "HDFCBK", "body": "123456 is your OTP. Do not share.", "otp": "123456"]))
send(frame(k, seq: 3, type: "clipboard", data: ["text": "hello from fake phone"]))
send(frame(k, seq: 3, type: "clipboard", data: ["text": "REPLAYED - must be ignored"]))
task.receive { r in
    if case .success(.data(let d)) = r, let p = try? ChaChaPoly.open(.init(combined: d), using: k) {
        print("reply from mac: \(String(data: p, encoding: .utf8) ?? "?")")
    }
}
Thread.sleep(forTimeInterval: 2)
// wrong key: daemon must drop the connection
send(frame(key(Data(repeating: 7, count: 32)), seq: 9, type: "clipboard", data: ["text": "BAD KEY"]))
Thread.sleep(forTimeInterval: 1.5)
print("closeCode after bad frame: \(task.closeCode.rawValue) (nonzero/1 = closed by daemon)")
