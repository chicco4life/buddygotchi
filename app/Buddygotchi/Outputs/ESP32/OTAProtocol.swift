import Foundation
import CryptoKit

// Wire-format helpers for OTA frames sent over the Nordic UART Service.
// Mirrors firmware/xfer.h's chunked-base64 envelope so Mac and device
// share the same parser shape.
//
// Frame budget: NUS MTU after macOS negotiation is ~185 bytes. The
// JSON envelope around a chunk (`{"cmd":"ota_chunk","seq":NNN,"d":"..."}`) eats
// ~30 bytes; base64 expands ~4/3. Net payload per chunk: ~110 raw bytes,
// which we round to 96 to keep frames comfortably under MTU and avoid
// fragmentation under the device's 256-byte RX ring.
enum OTAProtocol {
    static let chunkPayloadSize = 96

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func beginFrame(size: Int, sha256: String, version: String) -> Data {
        let json: [String: Any] = [
            "cmd": "ota_begin",
            "size": size,
            "sha256": sha256,
            "version": version,
        ]
        return jsonLine(json)
    }

    static func chunkFrame(seq: Int, payload: Data) -> Data {
        let b64 = payload.base64EncodedString()
        let json: [String: Any] = [
            "cmd": "ota_chunk",
            "seq": seq,
            "d": b64,
        ]
        return jsonLine(json)
    }

    static func endFrame(sha256: String) -> Data {
        let json: [String: Any] = [
            "cmd": "ota_end",
            "sha256": sha256,
        ]
        return jsonLine(json)
    }

    // Slice a binary into payload-sized chunks; index matches the seq
    // number sent on the wire so receiver can detect drops.
    static func chunks(of data: Data, size: Int = chunkPayloadSize) -> [Data] {
        var out: [Data] = []
        out.reserveCapacity((data.count + size - 1) / size)
        var offset = 0
        while offset < data.count {
            let end = min(offset + size, data.count)
            out.append(data.subdata(in: offset..<end))
            offset = end
        }
        return out
    }

    private static func jsonLine(_ obj: [String: Any]) -> Data {
        // Sort keys so test assertions don't depend on dictionary iteration order.
        var data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
        data.append(0x0A)
        return data
    }
}
