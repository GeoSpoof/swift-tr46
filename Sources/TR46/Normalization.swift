// Unicode Normalization Form C, for tr46's two uses of JavaScript's String.prototype.normalize("NFC").
//
// NFC follows UAX #15 (https://www.unicode.org/reports/tr15/) over the Unicode 18.0.0 data in
// Generated/NFCTables.swift, so its answer is the same on every OS. FoundationNFC, on Apple
// platforms only, uses the OS's own normalization data instead.
//
// Everything here takes and returns code points, and compares them as [UInt32]. String's == is
// canonical equivalence, which would hide exactly the difference validateLabel's step 1 tests for.

#if canImport(Darwin)
internal import Foundation
#endif

/// The NFC that both of tr46's NFC steps go through: processing's step 2, which normalizes the
/// whole mapped domain, and validateLabel's step 1, which checks a label is already in NFC.
struct Normalizer: Sendable {
    enum Mode: Sendable, Hashable {
        /// `NFC`, over the bundled Unicode 18.0.0 tables.
        case bundled
        #if canImport(Darwin)
        /// `FoundationNFC`, over the OS's data.
        case foundation
        #endif
    }

    let mode: Mode

    func nfc(_ codePoints: [UInt32]) -> [UInt32] {
        switch mode {
        case .bundled:
            return NFC.normalize(codePoints)
        #if canImport(Darwin)
        case .foundation:
            return FoundationNFC.normalize(codePoints)
        #endif
        }
    }

    func isNFC(_ codePoints: [UInt32]) -> Bool {
        switch mode {
        case .bundled:
            return NFC.isNormalized(codePoints)
        #if canImport(Darwin)
        case .foundation:
            return FoundationNFC.normalize(codePoints) == codePoints
        #endif
        }
    }
}

/// NFC over the bundled Unicode 18.0.0 tables.
enum NFC {
    enum QuickCheckResult: Equatable {
        case yes
        case no
        case maybe
    }

    /// UAX #15 §9's quick check: `.no` at a combining-class order violation or an NFC_QC=No code
    /// point, else `.maybe` if any code point is NFC_QC=Maybe, else `.yes`.
    static func quickCheck(_ codePoints: [UInt32]) -> QuickCheckResult {
        var lastClass: UInt8 = 0
        var result = QuickCheckResult.yes
        for codePoint in codePoints {
            let combiningClass = combiningClass(of: codePoint)
            if lastClass > combiningClass && combiningClass != 0 { return .no }
            if Lookup.contains(NFCTables.quickCheckNo, codePoint) { return .no }
            if Lookup.contains(NFCTables.quickCheckMaybe, codePoint) { result = .maybe }
            lastClass = combiningClass
        }
        return result
    }

    /// The NFC form of `codePoints`. Returns the input itself when the quick check says `.yes`.
    static func normalize(_ codePoints: [UInt32]) -> [UInt32] {
        if quickCheck(codePoints) == .yes { return codePoints }
        return decomposeAndCompose(codePoints)
    }

    /// Whether `codePoints` is already in NFC. Only a `.maybe` quick check needs the full algorithm.
    static func isNormalized(_ codePoints: [UInt32]) -> Bool {
        switch quickCheck(codePoints) {
        case .yes: return true
        case .no: return false
        case .maybe: return decomposeAndCompose(codePoints) == codePoints
        }
    }

    /// Canonical decomposition, canonical reordering, then canonical composition, without the
    /// quick-check shortcut.
    static func decomposeAndCompose(_ codePoints: [UInt32]) -> [UInt32] {
        var buffer = decompose(codePoints)
        var classes = buffer.map(combiningClass(of:))
        reorder(&buffer, &classes)
        compose(&buffer, classes)
        return buffer
    }

    /// Canonical_Combining_Class.
    static func combiningClass(of codePoint: UInt32) -> UInt8 {
        let starts = NFCTables.cccStarts
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= codePoint { low = middle } else { high = middle - 1 }
        }
        return NFCTables.cccValues[low]
    }

    // MARK: - Hangul (UAX #15 §16, Unicode §3.12)

    private static let sBase: UInt32 = 0xAC00
    private static let lBase: UInt32 = 0x1100
    private static let vBase: UInt32 = 0x1161
    private static let tBase: UInt32 = 0x11A7
    private static let lCount: UInt32 = 19
    private static let vCount: UInt32 = 21
    private static let tCount: UInt32 = 28
    private static let nCount: UInt32 = vCount * tCount
    private static let sCount: UInt32 = lCount * nCount

    // MARK: - Decomposition

    private static func decompose(_ codePoints: [UInt32]) -> [UInt32] {
        var output: [UInt32] = []
        output.reserveCapacity(codePoints.count)
        for codePoint in codePoints {
            if codePoint >= sBase && codePoint < sBase + sCount {
                let s = codePoint - sBase
                output.append(lBase + s / nCount)
                output.append(vBase + (s % nCount) / tCount)
                let t = s % tCount
                if t != 0 { output.append(tBase + t) }
            } else if let decomposition = decomposition(of: codePoint) {
                output.append(contentsOf: decomposition)
            } else {
                output.append(codePoint)
            }
        }
        return output
    }

    /// The full recursive canonical decomposition from the table, or nil when there is none.
    private static func decomposition(of codePoint: UInt32) -> ArraySlice<UInt32>? {
        let keys = NFCTables.decompositionKeys
        var low = 0
        var high = keys.count - 1
        while low <= high {
            let middle = (low + high) / 2
            if keys[middle] < codePoint {
                low = middle + 1
            } else if keys[middle] > codePoint {
                high = middle - 1
            } else {
                let entry = NFCTables.decompositionEntries[middle]
                let offset = Int(entry >> 3)
                let length = Int(entry & 0x7)
                return NFCTables.decompositionPool[offset..<(offset + length)]
            }
        }
        return nil
    }

    // MARK: - Canonical ordering

    /// Sorts each maximal run of non-starters stably by combining class. Short runs use an
    /// insertion sort; longer ones a stable merge sort, so a long run is O(k log k), not O(k²).
    private static func reorder(_ codePoints: inout [UInt32], _ classes: inout [UInt8]) {
        var start = 0
        while start < codePoints.count {
            if classes[start] == 0 {
                start += 1
                continue
            }
            var end = start + 1
            while end < codePoints.count && classes[end] != 0 { end += 1 }
            if end - start <= 16 {
                insertionSort(&codePoints, &classes, start, end)
            } else {
                mergeSort(&codePoints, &classes, start, end)
            }
            start = end
        }
    }

    private static func insertionSort(_ codePoints: inout [UInt32], _ classes: inout [UInt8], _ start: Int, _ end: Int) {
        var i = start + 1
        while i < end {
            let codePoint = codePoints[i]
            let combiningClass = classes[i]
            var j = i
            // Strictly greater, so equal classes keep their order.
            while j > start && classes[j - 1] > combiningClass {
                codePoints[j] = codePoints[j - 1]
                classes[j] = classes[j - 1]
                j -= 1
            }
            codePoints[j] = codePoint
            classes[j] = combiningClass
            i += 1
        }
    }

    /// A bottom-up merge sort that takes from the left run on ties, so it is stable.
    private static func mergeSort(_ codePoints: inout [UInt32], _ classes: inout [UInt8], _ start: Int, _ end: Int) {
        var source = Array(zip(classes[start..<end], codePoints[start..<end]))
        var target = source
        let count = source.count
        var width = 1
        while width < count {
            var low = 0
            while low < count {
                let middle = min(low + width, count)
                let high = min(low + 2 * width, count)
                var left = low
                var right = middle
                var k = low
                while left < middle && right < high {
                    if source[right].0 < source[left].0 {
                        target[k] = source[right]
                        right += 1
                    } else {
                        target[k] = source[left]
                        left += 1
                    }
                    k += 1
                }
                while left < middle {
                    target[k] = source[left]
                    left += 1
                    k += 1
                }
                while right < high {
                    target[k] = source[right]
                    right += 1
                    k += 1
                }
                low = high
            }
            swap(&source, &target)
            width *= 2
        }
        for (offset, element) in source.enumerated() {
            classes[start + offset] = element.0
            codePoints[start + offset] = element.1
        }
    }

    // MARK: - Composition

    /// UAX #15's sample composition algorithm. A character composes with the last starter unless
    /// something between them blocks it: `lastClass < chClass || lastClass == 0`. A string that
    /// begins with a non-starter starts at lastClass 256, so nothing composes with that first
    /// character. `classes` is the reordered input's combining classes.
    private static func compose(_ codePoints: inout [UInt32], _ classes: [UInt8]) {
        guard !codePoints.isEmpty else { return }
        var starterIndex = 0
        var starter = codePoints[0]
        var lastClass = classes[0] == 0 ? 0 : 256
        var write = 1
        var read = 1
        while read < codePoints.count {
            let character = codePoints[read]
            let characterClass = Int(classes[read])
            if lastClass < characterClass || lastClass == 0, let composite = primaryComposite(starter, character) {
                codePoints[starterIndex] = composite
                starter = composite
            } else {
                if characterClass == 0 {
                    starterIndex = write
                    starter = character
                }
                lastClass = characterClass
                codePoints[write] = character
                write += 1
            }
            read += 1
        }
        codePoints.removeLast(codePoints.count - write)
    }

    /// The primary composite of a pair: Hangul LV and LVT algorithmically, everything else from
    /// the table, which leaves out Full_Composition_Exclusion.
    private static func primaryComposite(_ first: UInt32, _ second: UInt32) -> UInt32? {
        if first >= lBase && first < lBase + lCount && second >= vBase && second < vBase + vCount {
            return sBase + ((first - lBase) * vCount + (second - vBase)) * tCount
        }
        if first >= sBase && first < sBase + sCount && (first - sBase) % tCount == 0 && second > tBase && second < tBase + tCount {
            return first + (second - tBase)
        }
        let key = UInt64(first) << 21 | UInt64(second)
        let keys = NFCTables.compositionKeys
        var low = 0
        var high = keys.count - 1
        while low <= high {
            let middle = (low + high) / 2
            if keys[middle] < key {
                low = middle + 1
            } else if keys[middle] > key {
                high = middle - 1
            } else {
                return NFCTables.compositionValues[middle]
            }
        }
        return nil
    }
}

#if canImport(Darwin)
/// Foundation's NFC, `precomposedStringWithCanonicalMapping`, which uses the OS's Unicode data.
enum FoundationNFC {
    static func normalize(_ codePoints: [UInt32]) -> [UInt32] {
        assert(
            !codePoints.contains { (0xD800...0xDFFF).contains($0) },
            "a lone surrogate reached NFC; tr46's flow refuses a decoded label holding one before step 1"
        )
        // A String can't hold a lone surrogate. Should one arrive anyway, it stays in place and the
        // text on each side is normalized on its own. That is JavaScript's answer too: a surrogate
        // is a starter that composes with nothing, so it splits the string into independent parts.
        var result: [UInt32] = []
        result.reserveCapacity(codePoints.count)
        var segment = String.UnicodeScalarView()
        for value in codePoints {
            if let scalar = Unicode.Scalar(value) {
                segment.append(scalar)
            } else {
                result.append(contentsOf: precomposed(segment))
                segment = String.UnicodeScalarView()
                result.append(value)
            }
        }
        result.append(contentsOf: precomposed(segment))
        return result
    }

    private static func precomposed(_ scalars: String.UnicodeScalarView) -> [UInt32] {
        if scalars.isEmpty { return [] }
        return String(scalars).precomposedStringWithCanonicalMapping.unicodeScalars.map(\.value)
    }
}
#endif
