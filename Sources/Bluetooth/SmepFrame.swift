import Foundation

/// Framing for the earbuds' second control channel, the "SPPSERVICE4" record
/// (`BudsModel.ServiceUUID.alternative`), which Samsung hosts use for SMEP.
///
/// The layout matches the standard SPP frame apart from the markers:
/// `FC | header (2, LE) | msgId | payload | CRC16 (2, LE) | CC`, where the
/// header's low 10 bits are the size of msgId + payload + CRC, and the CRC is
/// `CRC16.ccitt` over msgId + payload. Every frame seen on this channel uses
/// msgId 0x01 with a sub-id as the first payload byte, which is why this lives
/// apart from `SppMessage` and its `MessageId` enum.
enum SmepFrame {
    static let preamble: UInt8 = 0xFC
    static let postamble: UInt8 = 0xCC

    struct Message: Equatable {
        let messageId: UInt8
        let payload: Data
    }

    static func encode(messageId: UInt8, payload: Data) -> Data {
        let size = 1 + payload.count + 2 // msgId + payload + CRC
        let header = UInt16(size) & 0x3FF

        var body = Data([messageId])
        body.append(payload)
        let crc = CRC16.ccitt(body)

        var data = Data([preamble, UInt8(header & 0xFF), UInt8(header >> 8)])
        data.append(body)
        data.append(UInt8(crc & 0xFF))
        data.append(UInt8(crc >> 8))
        data.append(postamble)
        return data
    }

    /// Removes every complete frame from the front of `buffer` and returns
    /// them in order, leaving a trailing partial frame in place for the next
    /// read. Bytes that don't start a valid frame (wrong marker, bad CRC) are
    /// skipped one at a time so the parser resynchronises on the next `FC`.
    static func extractMessages(from buffer: inout Data) -> [Message] {
        var bytes = [UInt8](buffer)
        var messages: [Message] = []
        var start = 0

        while bytes.count - start >= 3 {
            guard bytes[start] == preamble else {
                start += 1
                continue
            }
            let size = Int(UInt16(bytes[start + 1]) | (UInt16(bytes[start + 2]) << 8)) & 0x3FF
            guard size >= 3 else {
                start += 1
                continue
            }
            let frameLength = size + 4
            guard bytes.count - start >= frameLength else { break }

            let body = Array(bytes[(start + 3)..<(start + 3 + size - 2)])
            let crcLow = bytes[start + 1 + size]
            let crcHigh = bytes[start + 2 + size]
            let storedCrc = UInt16(crcLow) | (UInt16(crcHigh) << 8)
            guard bytes[start + frameLength - 1] == postamble,
                  CRC16.ccitt(Data(body)) == storedCrc
            else {
                start += 1
                continue
            }

            messages.append(Message(messageId: body[0], payload: Data(body.dropFirst())))
            start += frameLength
        }

        bytes.removeFirst(start)
        buffer = Data(bytes)
        return messages
    }
}
