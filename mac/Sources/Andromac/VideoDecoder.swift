import Foundation
import AVFoundation
import AppKit
import CoreMedia

/// Turns Annex-B H.264 access units into sample buffers for an AVSampleBufferDisplayLayer.
final class VideoDecoder {
    private var format: CMVideoFormatDescription?
    private var sps: Data?, pps: Data?
    let layer = AVSampleBufferDisplayLayer()

    init() { layer.videoGravity = .resizeAspect; layer.backgroundColor = NSColor.black.cgColor }

    /// Returns false if we are still waiting for a keyframe.
    @discardableResult
    func decode(_ au: Data) -> Bool {
        var nals = VideoDecoder.split(au)
        for n in nals {
            switch n.first.map({ $0 & 0x1F }) {
            case 7: if sps != n { sps = n; format = nil }
            case 8: if pps != n { pps = n; format = nil }
            default: break
            }
        }
        if format == nil, let s = sps, let p = pps {
            let sb = [UInt8](s), pb = [UInt8](p)
            sb.withUnsafeBufferPointer { sp in pb.withUnsafeBufferPointer { pp in
                let ptrs = [sp.baseAddress!, pp.baseAddress!]
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2, parameterSetPointers: ptrs,
                    parameterSetSizes: [sb.count, pb.count], nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            } }
        }
        guard let fmt = format else { return false }
        nals.removeAll { [6, 7, 8, 9].contains($0.first.map { $0 & 0x1F } ?? 0) }
        guard !nals.isEmpty else { return true }
        var avcc = Data()
        for n in nals { var len = UInt32(n.count).bigEndian; avcc.append(Data(bytes: &len, count: 4)); avcc.append(n) }

        var block: CMBlockBuffer?
        let size = avcc.count
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: size, blockAllocator: nil,
                customBlockSource: nil, offsetToData: 0, dataLength: size, flags: 0, blockBufferOut: &block) == noErr, let b = block else { return true }
        avcc.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: b, offsetIntoDestination: 0, dataLength: size) }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sz = size
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: b, formatDescription: fmt, sampleCount: 1,
                sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &sz,
                sampleBufferOut: &sample) == noErr, let sb = sample else { return true }
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) as? [NSMutableDictionary] {
            arr.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        DispatchQueue.main.async {
            if self.layer.status == .failed { self.layer.flush() }
            self.layer.enqueue(sb)
        }
        return true
    }

    var videoSize: CGSize? { format.map { let d = CMVideoFormatDescriptionGetDimensions($0); return CGSize(width: Int(d.width), height: Int(d.height)) } }

    static func split(_ d: Data) -> [Data] {
        let b = [UInt8](d); var starts: [(Int, Int)] = []   // (index of start code, length of start code)
        var i = 0
        while i + 3 <= b.count {
            if b[i] == 0, b[i+1] == 0, b[i+2] == 1 { starts.append((i, 3)); i += 3 }
            else if i + 4 <= b.count, b[i] == 0, b[i+1] == 0, b[i+2] == 0, b[i+3] == 1 { starts.append((i, 4)); i += 4 }
            else { i += 1 }
        }
        var out: [Data] = []
        for (k, s) in starts.enumerated() {
            let from = s.0 + s.1, to = k + 1 < starts.count ? starts[k + 1].0 : b.count
            if to > from { out.append(Data(b[from..<to])) }
        }
        return out
    }
}
