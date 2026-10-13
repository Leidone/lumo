import Foundation

/// Strips tracking parameters from http(s) links, keeping everything else byte for byte.
public enum URLCleaner {
    private static let exact: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "yclid", "msclkid", "twclid", "ttclid", "li_fat_id",
        "igshid", "igsh", "si", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "vero_conv", "wickedid",
        "ref_src", "ref_url", "spm", "scm", "_openstat", "__s", "s_cid", "trk", "trkcampaign", "oly_anon_id", "oly_enc_id",
        "rb_clickid", "ns_source", "ns_mchannel", "ns_campaign", "ga_source", "ga_medium", "ga_campaign", "feature",
    ]
    private static let prefixes = ["utm_", "pk_", "mtm_", "hmb_", "itm_"]

    /// The cleaned link, or nil when the text isn't a link or has nothing to remove.
    public static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace), var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host != nil, let query = components.percentEncodedQuery
        else { return nil }
        let pairs = query.components(separatedBy: "&")
        let kept = pairs.filter { pair in
            let name = (pair.components(separatedBy: "=").first ?? "").lowercased()
            return !exact.contains(name) && !prefixes.contains { name.hasPrefix($0) }
        }
        guard kept.count != pairs.count else { return nil }
        components.percentEncodedQuery = kept.isEmpty ? nil : kept.joined(separator: "&")
        return components.string
    }
}
