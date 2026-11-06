import Foundation

/// What Battle.net's Agent knows about the products on this Mac: product.db, a bare protobuf message
/// with no account data in it. Blizzard documents neither; the field numbers are those of the GOG
/// Galaxy plugin's product_db.proto (MIT) and WowUp's reader (fields 6 and 13), checked on 6.11.2026
/// against the file Battle.net 2.53.8 writes on a Mac. Only ever read: the Agent owns the file. This
/// reads the few fields a library needs and steps over the rest, so a new Agent's fields do no harm.
enum ProductDB {
    /// What the Agent is doing to a product (`Operation` in the proto; none when the field is absent).
    enum Operation: Int, Equatable {
        case update = 0, backfill, repair
    }

    struct Install: Equatable {
        /// The Agent's name for it, often with a language ("s2_dede"): no key to go by.
        var uid = ""
        /// Blizzard's product code: wow, pro, fenris, hsb, and for the client itself bna and agent.
        var code = ""
        /// Field 6: the product's family ("wow"), from newer Agents.
        var family = ""
        /// As the client writes it: a Mac path, or under Wine "C:/Program Files (x86)/Overwatch".
        var installPath = ""
        var region = ""
        /// Field 13 of the settings: WoW's variant folder ("_retail_"), from newer Agents.
        var subfolder = ""
        var installed = false
        var playable = false
        var updateComplete = false
        var version = ""
        /// 0…1, of the update or download it last did.
        var progress: Double?
        var totalBytes: UInt64 = 0
        var remainingBytes: UInt64 = 0
        var operation: Operation?
    }

    /// The products listed, in the file's order. Nil for what isn't a whole product.db – empty, or cut
    /// off because the Agent was writing it: "couldn't be read" isn't "nothing installed".
    static func parse(_ data: Data) -> [Install]? {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }
        var installs: [Install] = []
        var database = Message(bytes[...])
        do {
            while let field = try database.next() {
                if field.number == 1, case .bytes(let product) = field.value { installs.append(try install(product)) }
            }
        } catch {
            return nil
        }
        return installs
    }

    private static func install(_ bytes: ArraySlice<UInt8>) throws -> Install {
        var install = Install()
        var message = Message(bytes)
        while let field = try message.next() {
            switch (field.number, field.value) {
            case (1, .bytes(let text)): install.uid = string(text)
            case (2, .bytes(let text)): install.code = string(text)
            case (3, .bytes(let settings)): try readSettings(settings, into: &install)
            case (4, .bytes(let state)): try readState(state, into: &install)
            case (5, .bytes(let operations)): try readOperations(operations, into: &install)
            case (6, .bytes(let text)): install.family = string(text)
            default: break
            }
        }
        return install
    }

    private static func readSettings(_ bytes: ArraySlice<UInt8>, into install: inout Install) throws {
        var message = Message(bytes)
        while let field = try message.next() {
            switch (field.number, field.value) {
            case (1, .bytes(let text)): install.installPath = string(text)
            case (2, .bytes(let text)): install.region = string(text)
            case (13, .bytes(let text)): install.subfolder = string(text)
            default: break
            }
        }
    }

    /// CachedProductState: base_product_state (1) and update_progress (4).
    private static func readState(_ bytes: ArraySlice<UInt8>, into install: inout Install) throws {
        var message = Message(bytes)
        while let field = try message.next() {
            guard case .bytes(let part) = field.value else { continue }
            var inner = Message(part)
            if field.number == 1 {
                while let state = try inner.next() {
                    switch (state.number, state.value) {
                    case (1, .varint(let flag)): install.installed = flag != 0
                    case (2, .varint(let flag)): install.playable = flag != 0
                    case (3, .varint(let flag)): install.updateComplete = flag != 0
                    case (7, .bytes(let text)): install.version = string(text)
                    default: break
                    }
                }
            } else if field.number == 4 {
                while let progress = try inner.next() {
                    switch (progress.number, progress.value) {
                    case (2, .fixed64(let bits)): install.progress = Double(bitPattern: bits)
                    case (4, .varint(let total)): install.totalBytes = total
                    case (5, .varint(let remaining)): install.remainingBytes = remaining
                    default: break
                    }
                }
            }
        }
    }

    /// `active_operation`: OP_NONE (-1) comes as ten bytes of varint, and fits no case.
    private static func readOperations(_ bytes: ArraySlice<UInt8>, into install: inout Install) throws {
        var message = Message(bytes)
        while let field = try message.next() {
            if field.number == 1, case .varint(let value) = field.value {
                install.operation = Operation(rawValue: Int(truncatingIfNeeded: value))
            }
        }
    }

    private static func string(_ bytes: ArraySlice<UInt8>) -> String {
        String(bytes: bytes, encoding: .utf8) ?? ""
    }

    // MARK: - Protobuf's wire format

    private enum Value {
        case varint(UInt64)
        case fixed64(UInt64)
        case fixed32(UInt32)
        case bytes(ArraySlice<UInt8>)
    }

    private struct Malformed: Error {}

    /// One message's fields, one after the other. Whatever doesn't add up throws; nothing reads past
    /// the message's end, whatever a length says.
    private struct Message {
        private var rest: ArraySlice<UInt8>

        init(_ bytes: ArraySlice<UInt8>) { rest = bytes }

        mutating func next() throws -> (number: Int, value: Value)? {
            guard !rest.isEmpty else { return nil }
            let key = try varint()
            let number = key >> 3
            guard number > 0, number <= 0x1FFF_FFFF else { throw Malformed() }
            switch key & 7 {
            case 0: return (Int(number), .varint(try varint()))
            case 1: return (Int(number), .fixed64(try fixed(8)))
            case 2:
                let length = try varint()
                guard length <= UInt64(rest.count) else { throw Malformed() }
                let value = rest.prefix(Int(length))
                rest = rest.dropFirst(Int(length))
                return (Int(number), .bytes(value))
            case 5: return (Int(number), .fixed32(UInt32(try fixed(4))))
            default: throw Malformed()  // groups, which proto3 has no use for, and wire types that don't exist
            }
        }

        private mutating func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<10 {
                guard let byte = rest.popFirst() else { throw Malformed() }
                value |= UInt64(byte & 0x7F) << UInt64(index * 7)
                if byte < 0x80 { return value }
            }
            throw Malformed()
        }

        private mutating func fixed(_ size: Int) throws -> UInt64 {
            guard rest.count >= size else { throw Malformed() }
            var value: UInt64 = 0
            for (index, byte) in rest.prefix(size).enumerated() { value |= UInt64(byte) << UInt64(index * 8) }
            rest = rest.dropFirst(size)
            return value
        }
    }
}
