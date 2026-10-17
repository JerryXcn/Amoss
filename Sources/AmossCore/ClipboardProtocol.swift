import Foundation

/// The clipboard-only subset of the bundled scrcpy 5.0.1 control protocol.
/// No key, touch, power, video or audio messages are used by this connection.
public enum ClipboardProtocol {
    public static let serverVersion = "5.0.1"
    public static let maximumTextBytes = (1 << 18) - 14

    public static func setText(_ text: String, sequence: UInt64) throws -> Data {
        let bytes = Data(text.utf8)
        guard bytes.count <= maximumTextBytes else { throw ClipboardProtocolError.textTooLong }
        var message = Data([9]) // SET_CLIPBOARD
        message.appendInteger(sequence)
        message.append(0) // Set only; never inject PASTE or change the focused app.
        message.appendInteger(UInt32(bytes.count))
        message.append(bytes)
        return message
    }

    public enum Message: Equatable, Sendable {
        case text(String)
        case acknowledgement(UInt64)
    }

    /// TCP may split a Chinese character, a length field or several messages
    /// arbitrarily. Reject oversized/unknown frames without allocating their size.
    public struct Decoder: Sendable {
        private var buffer = Data()
        public init() {}

        public mutating func append(_ data: Data) throws -> [Message] {
            buffer.append(data)
            var messages: [Message] = []
            var offset = 0
            while offset < buffer.count {
                switch buffer[offset] {
                case 0:
                    guard buffer.count - offset >= 5 else { break }
                    let count = Int(buffer.integer(at: offset + 1, bytes: 4))
                    guard count <= (1 << 18) - 5 else { throw ClipboardProtocolError.invalidMessage }
                    guard buffer.count - offset >= 5 + count else { break }
                    guard let text = String(data: buffer[(offset + 5)..<(offset + 5 + count)], encoding: .utf8) else {
                        throw ClipboardProtocolError.invalidMessage
                    }
                    messages.append(.text(text))
                    offset += 5 + count
                    continue
                case 1:
                    guard buffer.count - offset >= 9 else { break }
                    messages.append(.acknowledgement(buffer.integer(at: offset + 1, bytes: 8)))
                    offset += 9
                    continue
                default: throw ClipboardProtocolError.invalidMessage
                }
                break
            }
            // Rebase Data indices after consuming frames.
            if offset > 0 { buffer = Data(buffer.dropFirst(offset)) }
            guard buffer.count <= 1 << 18 else { throw ClipboardProtocolError.invalidMessage }
            return messages
        }
    }
}

public enum ClipboardProtocolError: LocalizedError {
    case textTooLong, invalidMessage, unavailable
    public var errorDescription: String? {
        switch self {
        case .textTooLong: L10n.text("文字过长，本次未同步（最多约 256 KB）。")
        case .invalidMessage: L10n.text("剪贴板连接返回了无效数据，正在重新连接。")
        case .unavailable: L10n.text("剪贴板连接暂不可用，正在重试。")
        }
    }
}

private extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        for shift in stride(from: T.bitWidth - 8, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
    func integer(at offset: Int, bytes: Int) -> UInt64 {
        self[offset..<(offset + bytes)].reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
