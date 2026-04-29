import Foundation

enum ANSIStripper {
    private static func decode(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? ""
    }

    static func strip(_ bytes: Data) -> String {
        let raw = Self.decode(bytes)
        var output = ""
        output.reserveCapacity(raw.count)
        var iterator = raw.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            if scalar == "\u{1B}" {
                skipEscape(iterator: &iterator)
                continue
            }
            if scalar == "\r" {
                continue
            }
            if scalar == "\u{07}" {
                continue
            }
            output.unicodeScalars.append(scalar)
        }
        return output
    }

    private static func skipEscape(iterator: inout String.UnicodeScalarView.Iterator) {
        guard let next = iterator.next() else { return }
        if next == "[" {
            skipCSI(iterator: &iterator)
            return
        }
        if next == "]" {
            skipOSC(iterator: &iterator)
            return
        }
        if next == "P" || next == "X" || next == "_" || next == "^" {
            skipUntilST(iterator: &iterator)
            return
        }
    }

    private static func skipCSI(iterator: inout String.UnicodeScalarView.Iterator) {
        while let scalar = iterator.next() {
            let value = scalar.value
            if value >= 0x40, value <= 0x7E { return }
        }
    }

    private static func skipOSC(iterator: inout String.UnicodeScalarView.Iterator) {
        while let scalar = iterator.next() {
            if scalar == "\u{07}" { return }
            if scalar == "\u{1B}" {
                if let following = iterator.next(), following == "\\" { return }
            }
        }
    }

    private static func skipUntilST(iterator: inout String.UnicodeScalarView.Iterator) {
        while let scalar = iterator.next() {
            if scalar == "\u{07}" { return }
            if scalar == "\u{1B}" {
                if let following = iterator.next(), following == "\\" { return }
            }
        }
    }
}
