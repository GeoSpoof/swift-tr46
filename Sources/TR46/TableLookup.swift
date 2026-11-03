// Ported from tr46 7.0.0 index.js (findStatus) and lib/statusMapping.js.
// Copyright (c) Sebastian Mayr. MIT; see LICENSE.
// index.js SHA-256 dd2eae4174a287b5a081feba8c41dd85d713d8b5185b5e98313c7ffe83834646

/// tr46's `STATUS_MAPPING` (lib/statusMapping.js). The generator asserts these values.
enum Status: UInt32 {
    case mapped = 1
    case valid = 2
    case disallowed = 3
    case deviation = 6
    case ignored = 7
}

/// Lookups over the generated tables.
enum Lookup {
    /// tr46's `findStatus(val)`: the status of `codePoint`, and its mapping (empty when it has none).
    ///
    /// tr46 binary-searches its raw rows. `IDNATables` merges adjacent rows only when their status
    /// and mapping are equal, so the run holding a code point gives the same pair. The runs cover
    /// 0…10FFFF without a gap (asserted by the generator), so unlike findStatus this never fails.
    static func status(of codePoint: UInt32) -> (Status, ArraySlice<UInt32>) {
        let starts = IDNATables.starts
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= codePoint { low = middle } else { high = middle - 1 }
        }
        let entry = IDNATables.entries[low]
        let length = Int((entry >> 3) & 0x1F)
        let offset = Int(entry >> 8)
        // Every entry holds one of the five statuses: the generator asserts it and TablesTests
        // decodes each one, so the fallback is unreachable.
        let status = Status(rawValue: entry & 0x7) ?? .disallowed
        return (status, IDNATables.mappingScalars[offset..<(offset + length)])
    }

    /// Membership of `codePoint` in `ranges`, sorted inclusive `[lo, hi]` pairs, flattened. This is
    /// how a regexes.js class (or a quick-check property) is tested.
    static func contains(_ ranges: [UInt32], _ codePoint: UInt32) -> Bool {
        var low = 0
        var high = ranges.count / 2 - 1
        while low <= high {
            let middle = (low + high) / 2
            if codePoint < ranges[2 * middle] {
                high = middle - 1
            } else if codePoint > ranges[2 * middle + 1] {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }
}
