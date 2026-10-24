import Foundation
import Security

enum TransferPhrase {
    static let wordCount = 4
    static let maximumInputBytes = 128
    // This exact dictionary is part of envelope v2 compatibility. Preserve its words;
    // changing which existing phrases can be imported needs an explicit format plan.
    private static let dictionary = Set(TransferWords.words)

    static func normalized(_ input: String) throws -> String {
        guard input.utf8.count <= maximumInputBytes else { throw invalidPhrase() }
        var words: [String] = []
        var word: [UInt8] = []
        for byte in input.utf8 {
            switch byte {
            case 32, 9, 10, 13, 45:
                if !word.isEmpty {
                    words.append(String(decoding: word, as: UTF8.self))
                    word.removeAll(keepingCapacity: true)
                    guard words.count <= wordCount else { throw invalidPhrase() }
                }
            case 65...90: word.append(byte + 32)
            case 97...122: word.append(byte)
            default: throw invalidPhrase()
            }
        }
        if !word.isEmpty { words.append(String(decoding: word, as: UTF8.self)) }
        guard words.count == wordCount, words.allSatisfy({ dictionary.contains($0) }) else { throw invalidPhrase() }
        return words.joined(separator: " ")
    }

    static func generate(randomUInt32: () throws -> UInt32 = secureUInt32) throws -> String {
        var words: [String] = []
        while words.count < wordCount {
            if let index = acceptedWordIndex(try randomUInt32(), dictionaryCount: TransferWords.words.count) {
                words.append(TransferWords.words[index])
            }
        }
        return words.joined(separator: " ")
    }

    // Reject the incomplete final bucket so every word has exactly the same probability.
    static func acceptedWordIndex(_ random: UInt32, dictionaryCount: Int) -> Int? {
        guard dictionaryCount > 0, UInt64(dictionaryCount) <= UInt64(UInt32.max) else { return nil }
        let range = UInt64(UInt32.max) + 1
        let count = UInt64(dictionaryCount)
        let limit = range - range % count
        guard UInt64(random) < limit else { return nil }
        return Int(UInt64(random) % count)
    }

    private static func secureUInt32() throws -> UInt32 {
        var value: UInt32 = 0
        guard SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &value) == errSecSuccess else {
            throw RoomTransfer.failure("Secure random generation failed. Try again.")
        }
        return value
    }

    private static func invalidPhrase() -> RemoteFailure {
        RoomTransfer.failure("Enter the four-word transfer phrase from the sending iPhone.")
    }
}
