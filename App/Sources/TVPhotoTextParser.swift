import Foundation

enum TVPhotoMACInterface: String, CaseIterable, Sendable {
    case wireless, wired, unspecified

    var title: String {
        switch self {
        case .wireless: "Wi-Fi"
        case .wired: "Ethernet"
        case .unspecified: "MAC address"
        }
    }
}

struct TVPhotoMACCandidate: Identifiable, Hashable, Sendable {
    let address: String
    let interface: TVPhotoMACInterface
    var id: String { interface.rawValue + "|" + address }
}

struct TVPhotoScanResult: Sendable, Equatable {
    var ipAddresses: [String]
    var macAddresses: [TVPhotoMACCandidate]
    var modelName: String?
}

/// Reads bounded OCR text, never QR contents. A field must have an explicit TV
/// network label; an incomplete or ambiguous read stays for the user to review.
/// In particular, no OCR character is replaced with a guessed digit.
enum TVPhotoTextParser {
    private enum Field {
        case ip, mac(TVPhotoMACInterface), model, ignored
    }

    private struct Label {
        let range: NSRange
        let field: Field
    }

    private static let wireless = #"(?:wi[\s-]?fi|wireless|wlan)"#
    private static let wired = #"(?:wired|ethernet|lan)"#
    private static let mac = #"MAC(?:\s+address)?"#
    private static let suffixSeparator = #"\s*(?:[:=]\s*)?"#

    private static let labels: NSRegularExpression = {
        let nonTV = #"(?:bluetooth|BT|remote(?:\s+control)?|smart\s+control|controller|phone|tablet|router|gateway)(?:\s+device)?"#
        let optionalIP = #"(?:\s+IP(?:v4)?)?(?:\s+address)?"#
        let ignored = [
            nonTV + #"\s+(?:IP(?:v4)?(?:\s+address)?|MAC(?:\s+address)?|address)"#,
            #"(?:default\s+)?gateway"# + optionalIP,
            #"(?:primary\s+|secondary\s+|preferred\s+|alternate\s+)?DNS(?:\s+server)?"# + optionalIP,
            #"subnet(?:\s+mask)?"# + optionalIP + #"|network\s+mask"# + optionalIP + #"|DHCP\s+server"# + optionalIP,
            #"(?:public|external|internet|WAN|router)\s+(?:IP(?:v4)?(?:\s+address)?|MAC(?:\s+address)?)"#,
            mac + suffixSeparator + #"\(\s*"# + nonTV + #"\s*\)"#,
            #"serial(?:\s+(?:number|no\.?|code))?"#,
            #"(?:pairing|device)\s+(?:id|code|token|hash|secret)"#,
            wireless + #"\s+(?:password|SSID|name)"#
        ].joined(separator: "|")
        let wirelessMAC = wireless + #"\s+"# + mac + "|" + mac + suffixSeparator + #"\(\s*"# + wireless + #"\s*\)"#
        let wiredMAC = wired + #"\s+"# + mac + "|" + mac + suffixSeparator + #"\(\s*"# + wired + #"\s*\)"#
        // Query-string keys and path segments are not labels on a TV screen.
        // Otherwise a URL's `?ip=` can split away the URL prefix before token
        // validation, making its private-IP parameter look like a real field.
        let pattern = #"(?<![\w./?:=&%#\-])\b(?:(?<ignored>"# + ignored + #")|(?<wireless>"# + wirelessMAC +
            #")|(?<wired>"# + wiredMAC + #")|(?<ip>(?:TV\s+)?IP(?:v4)?(?:\s+address)?)|(?<mac>(?:TV\s+)?"# +
            mac + #")|(?<model>model\s+(?:code|number|no\.?)))(?!\w)"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static let urlContext = try! NSRegularExpression(
        pattern: #"\b(?:[A-Za-z][A-Za-z0-9+.\-]{0,31}://|www\.|[A-Za-z0-9][A-Za-z0-9.\-]{0,253}\.[A-Za-z]{2,}(?::[0-9]{1,5})?[/?#])"#,
        options: [.caseInsensitive])

    private static let ipTokens = try! NSRegularExpression(
        pattern: #"(?<![\w.:/\-?=&%#])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![\w.:/\-?=&%#])"#)
    private static let macTokens = try! NSRegularExpression(
        pattern: #"(?<![\w.:/\-?=&%#])(?:[0-9A-F]{2}(?::[0-9A-F]{2}){5}|[0-9A-F]{2}(?:-[0-9A-F]{2}){5}|(?:[0-9A-F]{4}\.){2}[0-9A-F]{4}|[0-9A-F]{12})(?![\w.:/\-?=&%#])"#,
        options: [.caseInsensitive])
    private static let nonTVValue = try! NSRegularExpression(
        pattern: #"\b(?:bluetooth|BT|remote|controller|phone|tablet|router|gateway|serial|pairing)\b"#,
        options: [.caseInsensitive])
    private static let modelValue = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9][A-Za-z0-9 ._/\-]{0,79}$"#)

    static func parse(lines: [String]) -> TVPhotoScanResult {
        var result = TVPhotoScanResult(ipAddresses: [], macAddresses: [], modelName: nil)
        var models: [String] = []
        var pending: Field?
        var remainingBytes = 20_000

        for original in lines.prefix(200) {
            let byteCount = original.utf8.prefix(remainingBytes + 1).count
            guard byteCount <= remainingBytes else { break }
            remainingBytes -= byteCount
            // Skip an entire overlong row instead of truncating it into a
            // different valid address. This also bounds Unicode processing.
            let bounded = String(original.prefix(401))
            guard bounded.count <= 400 else {
                pending = nil
                continue
            }
            let text = original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { pending = nil; continue }
            let source = text as NSString
            guard urlContext.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) == nil else {
                pending = nil
                continue
            }
            let all = labels.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
                let field: Field
                if match.range(withName: "ignored").location != NSNotFound { field = .ignored }
                else if match.range(withName: "wireless").location != NSNotFound { field = .mac(.wireless) }
                else if match.range(withName: "wired").location != NSNotFound { field = .mac(.wired) }
                else if match.range(withName: "ip").location != NSNotFound { field = .ip }
                else if match.range(withName: "model").location != NSNotFound { field = .model }
                else { field = .mac(.unspecified) }
                return Label(range: match.range, field: field)
            }

            guard !all.isEmpty else {
                if let pending { collect(pending, value: text, result: &result, models: &models) }
                pending = nil // An address may follow its label by one row only.
                continue
            }

            pending = nil // Any new field label supersedes a previous empty one.
            for (index, label) in all.enumerated() {
                let start = NSMaxRange(label.range)
                let end = index + 1 < all.count ? all[index + 1].range.location : source.length
                let value = trimmedValue(source.substring(with: NSRange(location: start, length: end - start)))
                collect(label.field, value: value, result: &result, models: &models)
                // Only the final label can claim the immediately following row.
                // Adjacent empty column headings cannot identify a MAC's adapter.
                if index == all.count - 1, value.isEmpty {
                    if case .ignored = label.field {} else { pending = label.field }
                }
            }
        }

        // Multiple different model codes are ambiguous, just like addresses.
        result.modelName = models.count == 1 ? models[0] : nil
        return result
    }

    private static func trimmedValue(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":=|")))
    }

    private static func collect(_ field: Field, value: String, result: inout TVPhotoScanResult, models: inout [String]) {
        guard !value.isEmpty else { return }
        let nsValue = value as NSString
        let range = NSRange(location: 0, length: nsValue.length)
        switch field {
        case .ignored: break
        case .ip:
            guard !value.contains("/"), nonTVValue.firstMatch(in: value, range: range) == nil else { return }
            for match in ipTokens.matches(in: value, range: range) {
                let raw = nsValue.substring(with: match.range)
                guard let address = try? SamsungProtocol.privateHost(raw), !address.contains(":"),
                    !result.ipAddresses.contains(address) else { continue }
                result.ipAddresses.append(address)
            }
        case .mac(let interface):
            guard nonTVValue.firstMatch(in: value, range: range) == nil else { return }
            for match in macTokens.matches(in: value, range: range) {
                guard let address = try? SamsungWakeOnLAN.normalizedMAC(nsValue.substring(with: match.range)) else { continue }
                let candidate = TVPhotoMACCandidate(address: address, interface: interface)
                if interface == .unspecified {
                    guard !result.macAddresses.contains(where: { $0.address == address }) else { continue }
                } else {
                    result.macAddresses.removeAll { $0.address == address && $0.interface == .unspecified }
                    guard !result.macAddresses.contains(candidate) else { continue }
                }
                result.macAddresses.append(candidate)
            }
        case .model:
            let candidate = trimmedValue(value)
            guard candidate.count <= 80, modelValue.firstMatch(in: candidate, range: NSRange(location: 0, length: (candidate as NSString).length)) != nil,
                candidate.contains(where: { $0.isASCII && $0.isNumber }),
                candidate.contains(where: { $0.isASCII && $0.isLetter }), !models.contains(candidate) else { return }
            models.append(candidate)
        }
    }
}
