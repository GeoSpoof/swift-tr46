// Ported from punycode.js 2.3.1 (decode, encode, adapt, basicToDigit, digitToBasic).
// Copyright Mathias Bynens. MIT; see LICENSE.
// punycode.js SHA-256 6052a80eac47e46bd4de17ae0095e0192c336d3d7c387d292ad2176ebfc53d04

/// punycode.js's `decode` and `encode`, as tr46 7.0.0 calls them, with every `error(...)` returned
/// as nil. tr46 catches every Punycode error and treats it as a failure of the label, so nil is the
/// same outcome. punycode.js's `toASCII`, `toUnicode`, `mapDomain` and `ucs2.encode` are not
/// ported, because tr46 doesn't call them.
///
/// There are two implementations with the same arithmetic and the same checks in the same order:
///
/// - The literal one is punycode.js line for line, with its array insertion and its full scans of
///   the input, which are O(n²).
/// - The scalable one runs the same loops but places code points with a Fenwick tree, in
///   O(n log n). Quadratic Punycode decoding is a known denial-of-service class (CVE-2022-45061,
///   CPython's IDNA decoder).
///
/// `.automatic` uses the literal one up to `literalLimit` code points and the scalable one above
/// it. The tests force each over the same inputs.
///
/// All state is `Int64`. punycode.js computes in doubles, which hold every value it reaches
/// exactly; a 32-bit `Int`, as on watchOS arm64_32, would trap at `++delta` on `maxInt`.
enum Punycode {
    enum Strategy: Sendable {
        /// `literal` for inputs of at most `literalLimit` code points, `scalable` above that.
        case automatic
        /// punycode.js as written.
        case literal
        /// The same results in O(n log n).
        case scalable
    }

    /// The largest input `.automatic` gives to the literal implementation.
    static let literalLimit = 1_024

    /// Highest positive signed 32-bit float value
    private static let maxInt: Int64 = 2_147_483_647  // aka. 0x7FFFFFFF or 2^31-1

    /// Bootstring parameters
    private static let base: Int64 = 36
    private static let tMin: Int64 = 1
    private static let tMax: Int64 = 26
    private static let skew: Int64 = 38
    private static let damp: Int64 = 700
    private static let initialBias: Int64 = 72
    private static let initialN: Int64 = 128  // 0x80
    private static let delimiter: UInt32 = 0x2D  // '\x2D'

    /// Convenience shortcuts
    private static let baseMinusTMin = base - tMin

    // MARK: - Decode

    /// punycode.js's `decode(input)`: the raw decoded values, surrogate values included, before
    /// `String.fromCodePoint` (that is `JSString.fromCodePoints`). nil for every `error(...)`.
    ///
    /// `input` is code points. punycode.js reads UTF-16 units, which gives the same answer: see
    /// `JSString` (J7).
    static func decode(_ input: [UInt32], strategy: Strategy = .automatic) -> [UInt32]? {
        switch strategy {
        case .automatic:
            return input.count <= literalLimit ? decodeLiteral(input) : decodeScalable(input)
        case .literal:
            return decodeLiteral(input)
        case .scalable:
            return decodeScalable(input)
        }
    }

    private static func decodeLiteral(_ input: [UInt32]) -> [UInt32]? {
        // Don't use UCS-2.
        var output: [UInt32] = []
        let inputLength = input.count
        var i: Int64 = 0
        var n = initialN
        var bias = initialBias

        // Handle the basic code points: let `basic` be the number of input code
        // points before the last delimiter, or `0` if there is none, then copy
        // the first basic code points to the output.

        let basic = input.lastIndex(of: delimiter) ?? 0

        for j in 0..<basic {
            // if it's not a basic code point
            if input[j] >= 0x80 {
                return nil  // error('not-basic')
            }
            output.append(input[j])
        }

        // Main decoding loop: start just after the last delimiter if any basic code
        // points were copied; start at the beginning otherwise.

        var index = basic > 0 ? basic + 1 : 0
        while index < inputLength {
            // `index` is the index of the next character to be consumed.
            // Decode a generalized variable-length integer into `delta`,
            // which gets added to `i`. The overflow checking is easier
            // if we increase `i` as we go, then subtract off its starting
            // value at the end to obtain `delta`.
            let oldi = i
            var w: Int64 = 1
            var k = base
            while true {
                if index >= inputLength {
                    return nil  // error('invalid-input')
                }

                let digit = basicToDigit(input[index])
                index += 1

                if digit >= base {
                    return nil  // error('invalid-input')
                }
                if digit > (maxInt - i) / w {
                    return nil  // error('overflow')
                }

                i += digit * w
                let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)

                if digit < t {
                    break
                }

                let baseMinusT = base - t
                if w > maxInt / baseMinusT {
                    return nil  // error('overflow')
                }

                w *= baseMinusT
                k += base
            }

            let out = Int64(output.count + 1)
            bias = adapt(i - oldi, out, oldi == 0)

            // `i` was supposed to wrap around from `out` to `0`,
            // incrementing `n` each time, so we'll fix that now:
            if i / out > maxInt - n {
                return nil  // error('overflow')
            }

            n += i / out
            i %= out

            // Insert `n` at position `i` of the output.
            output.insert(UInt32(n), at: Int(i))
            i += 1
        }

        return output
    }

    /// The same loop as `decodeLiteral`, without the array: `out` is counted, and each insertion's
    /// position and value are recorded. Then the insertions are replayed from the last to the
    /// first: insertion j takes the position_j-th free slot (0-based) of the final output, found
    /// by binary lifting in a Fenwick tree of free slots. The basic code points fill the slots
    /// left over, in order, because insertions never reorder what is already there.
    private static func decodeScalable(_ input: [UInt32]) -> [UInt32]? {
        let inputLength = input.count
        var i: Int64 = 0
        var n = initialN
        var bias = initialBias

        let basic = input.lastIndex(of: delimiter) ?? 0
        for j in 0..<basic where input[j] >= 0x80 {
            return nil  // error('not-basic')
        }

        var positions: [Int] = []
        var values: [UInt32] = []
        var outputCount = basic

        var index = basic > 0 ? basic + 1 : 0
        while index < inputLength {
            let oldi = i
            var w: Int64 = 1
            var k = base
            while true {
                if index >= inputLength {
                    return nil  // error('invalid-input')
                }
                let digit = basicToDigit(input[index])
                index += 1
                if digit >= base {
                    return nil  // error('invalid-input')
                }
                if digit > (maxInt - i) / w {
                    return nil  // error('overflow')
                }
                i += digit * w
                let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                if digit < t {
                    break
                }
                let baseMinusT = base - t
                if w > maxInt / baseMinusT {
                    return nil  // error('overflow')
                }
                w *= baseMinusT
                k += base
            }

            let out = Int64(outputCount + 1)
            bias = adapt(i - oldi, out, oldi == 0)
            if i / out > maxInt - n {
                return nil  // error('overflow')
            }
            n += i / out
            i %= out

            positions.append(Int(i))
            values.append(UInt32(n))
            outputCount += 1
            i += 1
        }

        var output = [UInt32](repeating: 0, count: outputCount)
        var taken = [Bool](repeating: false, count: outputCount)
        var free = FenwickTree(ones: outputCount)
        for j in stride(from: positions.count - 1, through: 0, by: -1) {
            let slot = free.indexOfOne(atRank: positions[j])
            output[slot] = values[j]
            taken[slot] = true
            free.add(-1, at: slot)
        }
        var next = 0
        for slot in 0..<outputCount where !taken[slot] {
            output[slot] = input[next]
            next += 1
        }
        return output
    }

    // MARK: - Encode

    /// punycode.js's `encode(input)`: the Punycode digits as ASCII bytes, without the `xn--`
    /// prefix, or nil for `error('overflow')`.
    ///
    /// punycode.js starts with `ucs2decode(input)`. tr46's labels are already the code points of
    /// a JavaScript `for…of` loop, which are exactly what `ucs2decode` returns, so `input` is used
    /// as it is. Every value must be at most 0x10FFFF, which every label satisfies.
    static func encode(_ input: [UInt32], strategy: Strategy = .automatic) -> [UInt8]? {
        switch strategy {
        case .automatic:
            return input.count <= literalLimit ? encodeLiteral(input) : encodeScalable(input)
        case .literal:
            return encodeLiteral(input)
        case .scalable:
            return encodeScalable(input)
        }
    }

    private static func encodeLiteral(_ input: [UInt32]) -> [UInt8]? {
        var output: [UInt8] = []

        // Convert the input in UCS-2 to an array of Unicode code points.
        let input = input.map { Int64($0) }

        // Cache the length.
        let inputLength = Int64(input.count)

        // Initialize the state.
        var n = initialN
        var delta: Int64 = 0
        var bias = initialBias

        // Handle the basic code points.
        for currentValue in input {
            if currentValue < 0x80 {
                output.append(UInt8(currentValue))
            }
        }

        let basicLength = Int64(output.count)
        var handledCPCount = basicLength

        // `handledCPCount` is the number of code points that have been handled;
        // `basicLength` is the number of basic code points.

        // Finish the basic string with a delimiter unless it's empty.
        if basicLength > 0 {
            output.append(UInt8(delimiter))
        }

        // Main encoding loop:
        while handledCPCount < inputLength {
            // All non-basic code points < n have been handled already. Find the next
            // larger one:
            var m = maxInt
            for currentValue in input {
                if currentValue >= n && currentValue < m {
                    m = currentValue
                }
            }

            // Increase `delta` enough to advance the decoder's <n,i> state to <m,0>,
            // but guard against overflow.
            // punycode.js computes this once per round, and the loop below increments
            // handledCPCount without updating it (T10). Kept as written.
            let handledCPCountPlusOne = handledCPCount + 1
            if m - n > floorDivide(maxInt - delta, handledCPCountPlusOne) {
                return nil  // error('overflow')
            }

            delta += (m - n) * handledCPCountPlusOne
            n = m

            for currentValue in input {
                if currentValue < n {
                    delta += 1
                    if delta > maxInt {
                        return nil  // error('overflow')
                    }
                }
                if currentValue == n {
                    // Represent delta as a generalized variable-length integer.
                    emit(delta, bias, into: &output)
                    bias = adapt(delta, handledCPCountPlusOne, handledCPCount == basicLength)
                    delta = 0
                    handledCPCount += 1
                }
            }

            delta += 1
            n += 1
        }
        return output
    }

    /// The same rounds as `encodeLiteral`, one per distinct non-basic value in ascending order,
    /// without the full scans. Within a round for value m, `delta` grows by one for every value
    /// below m between consecutive occurrences of m, which a Fenwick tree over the positions of
    /// the values handled so far counts directly. Each of those increments is +1, so testing
    /// `delta > maxInt` after adding a whole gap fails exactly the inputs that the literal per-step
    /// test fails.
    private static func encodeScalable(_ input: [UInt32]) -> [UInt8]? {
        var output: [UInt8] = []
        let inputLength = input.count
        var n = initialN
        var delta: Int64 = 0
        var bias = initialBias

        // Below n: counted. The basic code points are below every non-basic value.
        var below = FenwickTree(count: inputLength)
        for (position, currentValue) in input.enumerated() where currentValue < 0x80 {
            output.append(UInt8(currentValue))
            below.add(1, at: position)
        }

        let basicLength = Int64(output.count)
        var handledCPCount = basicLength
        if basicLength > 0 {
            output.append(UInt8(delimiter))
        }

        // The positions of the non-basic values, by value and then position.
        let nonBasic = input.indices
            .filter { input[$0] >= 0x80 }
            .sorted { (input[$0], $0) < (input[$1], $1) }

        var start = 0
        while start < nonBasic.count {
            let m = Int64(input[nonBasic[start]])
            var end = start
            while end < nonBasic.count && Int64(input[nonBasic[end]]) == m { end += 1 }

            let handledCPCountPlusOne = handledCPCount + 1
            if m - n > floorDivide(maxInt - delta, handledCPCountPlusOne) {
                return nil  // error('overflow')
            }
            delta += (m - n) * handledCPCountPlusOne
            n = m

            var previous = -1
            for position in nonBasic[start..<end] {
                delta += Int64(below.sum(from: previous + 1, to: position))
                if delta > maxInt {
                    return nil  // error('overflow')
                }
                emit(delta, bias, into: &output)
                bias = adapt(delta, handledCPCountPlusOne, handledCPCount == basicLength)
                delta = 0
                handledCPCount += 1
                previous = position
            }
            delta += Int64(below.sum(from: previous + 1, to: inputLength))
            if delta > maxInt {
                return nil  // error('overflow')
            }
            for position in nonBasic[start..<end] {
                below.add(1, at: position)
            }

            delta += 1
            n += 1
            start = end
        }
        return output
    }

    /// Represent delta as a generalized variable-length integer: the body of punycode.js's
    /// `if (currentValue === n)` block, up to the `adapt` call.
    private static func emit(_ delta: Int64, _ bias: Int64, into output: inout [UInt8]) {
        var q = delta
        var k = base
        while true {
            let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
            if q < t {
                break
            }
            let qMinusT = q - t
            let baseMinusT = base - t
            output.append(digitToBasic(t + qMinusT % baseMinusT))
            q = qMinusT / baseMinusT
            k += base
        }
        output.append(digitToBasic(q))
    }

    // MARK: - Helpers

    /// Converts a basic code point into a digit/integer: 0–9 → 26–35, A–Z and a–z → 0–25, or
    /// `base` if the code point does not represent a value.
    private static func basicToDigit(_ codePoint: UInt32) -> Int64 {
        if codePoint >= 0x30 && codePoint < 0x3A {
            return 26 + Int64(codePoint - 0x30)
        }
        if codePoint >= 0x41 && codePoint < 0x5B {
            return Int64(codePoint - 0x41)
        }
        if codePoint >= 0x61 && codePoint < 0x7B {
            return Int64(codePoint - 0x61)
        }
        return base
    }

    /// Converts a digit/integer into a basic code point: 0–25 → a–z, 26–35 → 0–9. tr46 always
    /// passes `flag` 0, so this is the lower-case form.
    private static func digitToBasic(_ digit: Int64) -> UInt8 {
        //  0..25 map to ASCII a..z or A..Z
        // 26..35 map to ASCII 0..9
        UInt8(digit + 22 + 75 * (digit < 26 ? 1 : 0))
    }

    /// Bias adaptation function as per section 3.4 of RFC 3492.
    /// https://tools.ietf.org/html/rfc3492#section-3.4
    private static func adapt(_ delta: Int64, _ numPoints: Int64, _ firstTime: Bool) -> Int64 {
        var k: Int64 = 0
        var delta = firstTime ? delta / damp : delta >> 1
        delta += delta / numPoints
        while delta > (baseMinusTMin * tMax) >> 1 {
            delta /= baseMinusTMin
            k += base
        }
        return k + (baseMinusTMin + 1) * delta / (delta + skew)
    }

    /// JavaScript's `Math.floor(a / b)` for a positive `b`. Swift's `/` truncates toward zero, which
    /// differs for a negative `a`. In encode's overflow guard `a` is `maxInt - delta`. At the start
    /// of a round, `delta` is at most one more than the number of positions after the previous
    /// round's last emitted code point, so `a` can only be negative for an input of at least 2^31
    /// code points. punycode.js refuses that case and truncation would not, so the guard floors
    /// anyway. Every other division in this file has a non-negative dividend, where the two agree,
    /// and every quotient is below 2^53, so the double division punycode.js does is exact.
    private static func floorDivide(_ a: Int64, _ b: Int64) -> Int64 {
        a >= 0 ? a / b : -((-a + b - 1) / b)
    }
}

/// A Fenwick (binary indexed) tree of counts over positions 0..<count.
private struct FenwickTree {
    /// 1-based: tree[i] holds the sum over (i - lowbit(i), i].
    private var tree: [Int]

    init(count: Int) {
        tree = [Int](repeating: 0, count: count + 1)
    }

    /// Every position holds 1. Built in O(n): the node for i covers lowbit(i) positions.
    init(ones count: Int) {
        tree = [Int](repeating: 0, count: count + 1)
        for index in stride(from: 1, through: count, by: 1) {
            tree[index] = index & -index
        }
    }

    mutating func add(_ value: Int, at position: Int) {
        var index = position + 1
        while index < tree.count {
            tree[index] += value
            index += index & -index
        }
    }

    /// The sum over positions 0..<end.
    private func prefixSum(_ end: Int) -> Int {
        var sum = 0
        var index = end
        while index > 0 {
            sum += tree[index]
            index -= index & -index
        }
        return sum
    }

    /// The sum over positions start..<end; zero when the range is empty.
    func sum(from start: Int, to end: Int) -> Int {
        end > start ? prefixSum(end) - prefixSum(start) : 0
    }

    /// For a tree of 0s and 1s, the position of the 1 with `rank` 1s before it, by binary lifting.
    /// The caller guarantees there are more than `rank` 1s.
    func indexOfOne(atRank rank: Int) -> Int {
        let count = tree.count - 1
        var position = 0
        var remaining = rank + 1
        var step = 1
        while step * 2 <= count { step *= 2 }
        while step > 0 {
            let next = position + step
            if next <= count && tree[next] < remaining {
                position = next
                remaining -= tree[next]
            }
            step /= 2
        }
        return position
    }
}
