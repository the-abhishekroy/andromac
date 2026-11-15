import AppKit
import CryptoKit

/// Clipboard images: shrink to a sane size and encode (PNG when transparent, otherwise JPEG) so they sync fast.
enum ImageCodec {
    static let maxSide: CGFloat = 2048

    static func sha(_ d: Data) -> String { Insecure.SHA1.hash(data: d).map { String(format: "%02x", $0) }.joined().prefix(20).description }

    /// Returns the bytes to sync and their mime type, or nil if `src` isn't a decodable image or is too big.
    static func prepare(_ src: Data) -> (Data, String)? {
        guard let rep = NSBitmapImageRep(data: src) else { return nil }
        var rep2 = rep
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        if max(w, h) > maxSide, let img = NSImage(data: src) {
            let k = maxSide / max(w, h), size = NSSize(width: w * k, height: h * k)
            let out = NSImage(size: size); out.lockFocus(); img.draw(in: NSRect(origin: .zero, size: size)); out.unlockFocus()
            if let t = out.tiffRepresentation, let r = NSBitmapImageRep(data: t) { rep2 = r }
        }
        let png = rep2.hasAlpha
        guard let data = png ? rep2.representation(using: .png, properties: [:]) : rep2.representation(using: .jpeg, properties: [.compressionFactor: 0.88]),
              data.count <= 6_000_000 else { return nil }
        return (data, png ? "image/png" : "image/jpeg")
    }
}
