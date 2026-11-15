import Foundation
import ScreenCaptureKit
import VideoToolbox
import CoreMedia

/// Captures the main display, encodes H.264 and hands Annex-B access units to `onPacket`.
final class MacScreenShare: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var session: VTCompressionSession?
    private var lastBuffer: CVPixelBuffer?
    private var forceKey = true
    private let queue = DispatchQueue(label: "andromac.capture")
    var onPacket: ((Bool, Data) -> Void)?
    var onStopped: (() -> Void)?
    private(set) var size = CGSize.zero
    private var bitrate = 5_000_000
    private var lastCongestion = Date.distantPast
    private var recovery: Timer?

    /// The link backed up: send a keyframe soon and lower the bitrate; it climbs back slowly while the link is calm.
    func congestion() {
        queue.async { [self] in
            lastCongestion = Date()
            bitrate = max(1_200_000, bitrate * 3 / 4)
            if let s = session { VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber) }
            forceKey = true
            if let b = lastBuffer { encode(b) }
        }
        DispatchQueue.main.async { [self] in
            if recovery == nil {
                recovery = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.queue.async {
                        guard Date().timeIntervalSince(self.lastCongestion) > 4, self.bitrate < 8_000_000, let s = self.session else { return }
                        self.bitrate = min(8_000_000, self.bitrate * 11 / 10)
                        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: self.bitrate as CFNumber)
                    }
                }
            }
        }
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let d = content.displays.first else { throw NSError(domain: "andromac", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display"]) }
        let scale = min(1, 1600 / CGFloat(max(d.width, d.height)))
        let w = Int(CGFloat(d.width) * scale) / 2 * 2, h = Int(CGFloat(d.height) * scale) / 2 * 2
        size = CGSize(width: w, height: h)

        let cfg = SCStreamConfiguration()
        cfg.width = w; cfg.height = h
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        cfg.showsCursor = true; cfg.queueDepth = 4
        try makeSession(w, h)
        let s = SCStream(filter: SCContentFilter(display: d, excludingWindows: []), configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    func stop() {
        let s = stream; stream = nil
        Task { try? await s?.stopCapture() }
        if let ss = session { VTCompressionSessionInvalidate(ss) }
        session = nil; lastBuffer = nil
        recovery?.invalidate(); recovery = nil
    }

    /// New viewer joined: emit a keyframe now (re-encoding the last frame if the screen is static).
    func requestKeyframe() {
        queue.async { [self] in
            forceKey = true
            if let b = lastBuffer { encode(b) }
        }
    }

    private func makeSession(_ w: Int, _ h: Int) throws {
        var s: VTCompressionSession?
        guard VTCompressionSessionCreate(allocator: nil, width: Int32(w), height: Int32(h), codecType: kCMVideoCodecType_H264,
                encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
                outputCallback: nil, refcon: nil, compressionSessionOut: &s) == noErr, let sess = s else {
            throw NSError(domain: "andromac", code: 2, userInfo: [NSLocalizedDescriptionKey: "Encoder unavailable"])
        }
        func set(_ k: CFString, _ v: CFTypeRef) { VTSessionSetProperty(sess, key: k, value: v) }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, 60 as CFNumber)
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 3 as CFNumber)
        set(kVTCompressionPropertyKey_MaxFrameDelayCount, 0 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(sess)
        session = sess
    }

    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let att = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = att[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        lastBuffer = pb
        encode(pb)
    }

    func stream(_ s: SCStream, didStopWithError error: Error) { onStopped?() }

    private func encode(_ pb: CVPixelBuffer) {
        guard let sess = session else { return }
        var props: CFDictionary?
        if forceKey { props = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary; forceKey = false }
        let pts = CMClockGetTime(CMClockGetHostTimeClock())
        VTCompressionSessionEncodeFrame(sess, imageBuffer: pb, presentationTimeStamp: pts, duration: .invalid,
                                        frameProperties: props, infoFlagsOut: nil) { [weak self] status, _, sb in
            guard status == noErr, let sb, let self else { return }
            let (key, data) = MacScreenShare.annexB(sb)
            self.onPacket?(key, data)
        }
    }

    /// AVCC (length-prefixed) → Annex-B, prepending SPS/PPS on keyframes.
    static func annexB(_ sb: CMSampleBuffer) -> (Bool, Data) {
        let start = Data([0, 0, 0, 1])
        var key = true
        if let a = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]], let f = a.first {
            key = !(f[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        }
        var out = Data()
        if key, let fmt = CMSampleBufferGetFormatDescription(sb) {
            for i in 0..<2 {
                var p: UnsafePointer<UInt8>?; var n = 0
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &n,
                                                                      parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr, let p {
                    out.append(start); out.append(p, count: n)
                }
            }
        }
        guard let block = CMSampleBufferGetDataBuffer(sb) else { return (key, out) }
        var len = 0; var ptr: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
        guard let ptr else { return (key, out) }
        let raw = UnsafeRawPointer(ptr); var off = 0
        while off + 4 <= len {
            let n = Int(UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: off, as: UInt32.self)))
            off += 4
            guard n > 0, off + n <= len else { break }
            out.append(start); out.append(Data(bytes: raw + off, count: n)); off += n
        }
        return (key, out)
    }
}
