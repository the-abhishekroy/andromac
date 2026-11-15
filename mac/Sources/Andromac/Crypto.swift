import Foundation
import CryptoKit

/// Frame format: nonce(12) || ciphertext || tag(16)  (ChaCha20-Poly1305)
struct Channel {
    let key: SymmetricKey

    init(secret: Data) {
        key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: Data("andromac-v1".utf8),
            info: Data("msg-key".utf8),
            outputByteCount: 32)
    }

    func seal(_ plaintext: Data) throws -> Data {
        try ChaChaPoly.seal(plaintext, using: key).combined
    }

    func open(_ frame: Data) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: frame), using: key)
    }
}

func loadOrCreateSecret() -> Data {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".andromac")
    let file = dir.appendingPathComponent("secret")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    if let d = try? Data(contentsOf: file), d.count == 32 { return d }
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
    let d = Data(bytes)
    try? d.write(to: file, options: .atomic)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    return d
}

extension Data {
    func base64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
