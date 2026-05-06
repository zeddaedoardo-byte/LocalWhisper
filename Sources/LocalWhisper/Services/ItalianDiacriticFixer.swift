import Foundation

// Deterministic, microsecond-fast pre-pass that restores Italian diacritics
// on a small set of unambiguous word forms that Whisper Large V3 Turbo
// frequently mistranscribes without accents.
//
// The list is intentionally conservative: every entry is a word form whose
// non-accented spelling is NOT a valid Italian word. This avoids the
// classic false-positive trap (`e -> è`, `pero -> però`, `da -> dà`,
// `ne -> né`) where the unaccented form is also a real word in another
// part of speech.
//
// Runs on every transcript regardless of language settings. The
// substitutions are word-bounded, so applying them to English text is a
// no-op (no English word matches any of the keys).
enum ItalianDiacriticFixer {

    // Map of unaccented spelling -> correctly accented spelling. Lowercase
    // keys; case-restoration is handled at substitution time so we preserve
    // sentence-initial capitalization and ALL-CAPS variants.
    //
    // Wrong-accent variants are also mapped (perchè -> perché) because
    // Whisper occasionally emits the grave-accent form for `perché` etc.
    private static let map: [(pattern: String, replacement: String)] = [
        ("perche",      "perché"),
        ("perchè",      "perché"),  // grave-accent typo
        ("poiche",      "poiché"),
        ("poichè",      "poiché"),
        ("benche",      "benché"),
        ("benchè",      "benché"),
        ("affinche",    "affinché"),
        ("affinchè",    "affinché"),
        ("nonche",      "nonché"),
        ("nonchè",      "nonché"),
        ("sicche",      "sicché"),
        ("sicchè",      "sicché"),
        ("finche",      "finché"),
        ("finchè",      "finché"),
        ("cioe",        "cioè"),
        ("cosi",        "così"),
        ("piu",         "più"),
        ("gia",         "già"),
        ("puo",         "può"),
        ("citta",       "città"),
        ("liberta",     "libertà"),
        ("verita",      "verità"),
        ("qualita",     "qualità"),
        ("realta",      "realtà"),
        ("difficolta",  "difficoltà"),
        ("possibilita", "possibilità"),
        ("societa",     "società"),
        ("attivita",    "attività"),
        // Removed: "eta" / "meta" / "papa" / "pieta" / "tribu". Each has a
        // legitimate non-accented form that would be corrupted by the fixer:
        // - "Meta" / "META": brand name, English preposition, proper noun.
        // - "ETA": acronym (Estimated Time of Arrival).
        // - "Papa" / "PAPA": "the Pope" (Italian capitalized) or surname.
        // - "Pieta" / "Tribu": rare proper nouns / non-Italian forms.
        // Italian "età", "metà", "papà", "pietà", "tribù" without accents
        // are real ambiguities; let the LLM (or the user) handle them.
        ("virtu",       "virtù"),
        ("gioventu",    "gioventù"),
        ("schiavitu",   "schiavitù"),
        ("servitu",     "servitù"),
        ("lunedi",      "lunedì"),
        ("martedi",     "martedì"),
        ("mercoledi",   "mercoledì"),
        ("giovedi",     "giovedì"),
        ("venerdi",     "venerdì"),
        ("cosicche",    "cosicché"),
        ("cosicchè",    "cosicché")
    ]

    private static let regexes: [(NSRegularExpression, String)] = {
        map.compactMap { entry in
            // Word-boundary anchors keep matches inside larger words intact:
            // `gia` matches "gia" but not "giallo" or "gianni". Critical to
            // avoid corrupting unrelated tokens.
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: entry.pattern))\\b"
            // Case insensitive so we catch sentence-initial and ALL-CAPS;
            // the replacement function below restores the original case.
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, entry.replacement)
        }
    }()

    static func fix(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        var result = input
        for (regex, replacement) in regexes {
            result = applyPreservingCase(regex: regex, in: result, with: replacement)
        }
        return result
    }

    // Apply a regex substitution while preserving the original token's case
    // pattern: lowercase, Title Case, or ALL CAPS. We don't try to handle
    // mixed-case words (those are unlikely matches anyway).
    private static func applyPreservingCase(regex: NSRegularExpression,
                                             in text: String,
                                             with replacement: String) -> String {
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        // Walk matches back-to-front so earlier ranges stay valid as we
        // substitute later ones.
        var output = nsText.mutableCopy() as! NSMutableString
        for match in matches.reversed() {
            let original = nsText.substring(with: match.range)
            let cased = caseAdjusted(replacement: replacement, like: original)
            output.replaceCharacters(in: match.range, with: cased)
        }
        return output as String
    }

    private static func caseAdjusted(replacement: String, like sample: String) -> String {
        if sample == sample.uppercased() && sample.count > 1 {
            return replacement.uppercased()
        }
        if let first = sample.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}
