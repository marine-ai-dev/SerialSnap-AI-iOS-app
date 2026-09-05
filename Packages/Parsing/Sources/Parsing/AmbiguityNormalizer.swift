import Foundation

/// Conservative OCR character-ambiguity handling.
///
/// We NEVER blind-replace an ambiguous glyph in the primary reading — a
/// mis-substitution would silently corrupt a serial number. Instead this
/// type generates a bounded set of *alternate* readings for a token by
/// swapping commonly-confused OCR character pairs, so the UI can offer
/// "did you mean" alternates during human review, and the parser can
/// cross-check candidates against a barcode read when one is available.
public enum AmbiguityNormalizer {

    /// Each tuple is a pair of glyphs Vision/OCR commonly confuses.
    /// Order-independent: either member may appear where the other belongs.
    public static let confusablePairs: [(Character, Character)] = [
        ("O", "0"),
        ("I", "1"),
        ("l", "1"),
        ("S", "5"),
        ("B", "8"),
        ("Z", "2"),
        ("G", "6"),
    ]

    /// Positions within `token` whose character is part of a confusable pair.
    public static func ambiguousIndices(in token: String) -> [Int] {
        let chars = Array(token)
        var result: [Int] = []
        for (i, c) in chars.enumerated() {
            if confusablePairs.contains(where: { $0.0 == c || $0.1 == c }) {
                result.append(i)
            }
        }
        return result
    }

    /// Generates alternate readings of `token` by substituting each
    /// ambiguous character with its confusable counterpart, one substitution
    /// at a time (single-flip alternates), capped at `maxAlternates` to
    /// avoid combinatorial blowup on long noisy tokens. The original token
    /// is never included in the result.
    public static func alternates(for token: String, maxAlternates: Int = 8) -> [String] {
        guard !token.isEmpty else { return [] }
        let chars = Array(token)
        var results: [String] = []
        for i in ambiguousIndices(in: token) {
            let c = chars[i]
            guard let pair = confusablePairs.first(where: { $0.0 == c || $0.1 == c }) else { continue }
            let replacement = (pair.0 == c) ? pair.1 : pair.0
            var variant = chars
            variant[i] = replacement
            let candidate = String(variant)
            if candidate != token && !results.contains(candidate) {
                results.append(candidate)
            }
            if results.count >= maxAlternates { break }
        }
        return results
    }

    /// True if `a` and `b` are identical, or differ only by confusable
    /// characters at the same positions (used to confirm OCR/barcode
    /// agreement even when one channel misread a glyph).
    public static func matchesAllowingConfusables(_ a: String, _ b: String) -> Bool {
        let ac = Array(a.uppercased())
        let bc = Array(b.uppercased())
        guard ac.count == bc.count else { return false }
        for (x, y) in zip(ac, bc) {
            if x == y { continue }
            let confusable = confusablePairs.contains { ($0.0 == x || $0.1 == x) && ($0.0 == y || $0.1 == y) }
            if !confusable { return false }
        }
        return true
    }
}
