import XCTest
@testable import RoomRemote

final class TransferPhraseTests: XCTestCase {
    private let phrase = "cable lunar velvet walnut"

    func testAuditedDictionaryIsUniqueASCIIAndFitsFourWordDisplayBound() {
        XCTAssertEqual(TransferWords.words.count, 7_772)
        XCTAssertEqual(Set(TransferWords.words).count, TransferWords.words.count)
        for word in TransferWords.words {
            XCTAssertFalse(word.isEmpty)
            XCTAssertLessThanOrEqual(word.utf8.count, 9)
            XCTAssertTrue(word.utf8.allSatisfy { 97...122 ~= $0 }, word)
        }
        XCTAssertLessThanOrEqual(4 * 9 + 3, 39)
    }

    func testNormalizationAcceptsASCIICaseAndConvenientSeparators() throws {
        for input in [phrase, "CABLE LUNAR VELVET WALNUT", "cable-lunar-velvet-walnut", " \tCaBlE\r\nLUNAR--velvet \t walnut\n"] {
            XCTAssertEqual(try TransferPhrase.normalized(input), phrase)
        }
        let exactlyBounded = String(repeating: " ", count: TransferPhrase.maximumInputBytes - phrase.utf8.count) + phrase
        XCTAssertEqual(exactlyBounded.utf8.count, TransferPhrase.maximumInputBytes)
        XCTAssertEqual(try TransferPhrase.normalized(exactlyBounded), phrase)
    }

    func testOrderAndRepeatedWordsArePreserved() throws {
        XCTAssertEqual(try TransferPhrase.normalized("walnut velvet lunar cable"), "walnut velvet lunar cable")
        XCTAssertNotEqual(try TransferPhrase.normalized("walnut velvet lunar cable"), phrase)
        XCTAssertEqual(try TransferPhrase.normalized("cable cable cable cable"), "cable cable cable cable")
    }

    func testMalformedNonASCIIUnknownAndOverlongPhrasesReject() {
        for input in ["", "cable lunar velvet", phrase + " cable", "unknownword lunar velvet walnut", "cable,lunar velvet walnut", "cable.lunar velvet walnut", "cable/lunar velvet walnut", "cable\u{00a0}lunar velvet walnut", "cable lunar velvét walnut", "CABLE LUNAR VELVET WALNÜT", "cable\0lunar velvet walnut", "cable lunar velvet walnut!", String(repeating: " ", count: 129), String(repeating: " ", count: 129 - phrase.utf8.count) + phrase] {
            XCTAssertThrowsError(try TransferPhrase.normalized(input), input)
        }
    }

    func testUniformIndexRejectsIncompleteBucketAndAcceptsItsExactBoundary() throws {
        let count = TransferWords.words.count
        let range = UInt64(UInt32.max) + 1
        let limit = range - range % UInt64(count)
        XCTAssertGreaterThan(range % UInt64(count), 0)
        XCTAssertEqual(TransferPhrase.acceptedWordIndex(0, dictionaryCount: count), 0)
        XCTAssertEqual(TransferPhrase.acceptedWordIndex(UInt32(count - 1), dictionaryCount: count), count - 1)
        XCTAssertEqual(TransferPhrase.acceptedWordIndex(UInt32(count), dictionaryCount: count), 0)
        XCTAssertEqual(TransferPhrase.acceptedWordIndex(UInt32(limit - 1), dictionaryCount: count), count - 1)
        XCTAssertNil(TransferPhrase.acceptedWordIndex(UInt32(limit), dictionaryCount: count))
        XCTAssertNil(TransferPhrase.acceptedWordIndex(UInt32.max, dictionaryCount: count))
        XCTAssertEqual(TransferPhrase.acceptedWordIndex(UInt32.max, dictionaryCount: 2), 1)
        XCTAssertNil(TransferPhrase.acceptedWordIndex(0, dictionaryCount: 0))
        XCTAssertNil(TransferPhrase.acceptedWordIndex(0, dictionaryCount: -1))
        XCTAssertNil(TransferPhrase.acceptedWordIndex(0, dictionaryCount: Int(UInt32.max) + 1))
    }

    func testGenerationRetriesRejectedRandomValueAndProducesFourDictionaryWords() throws {
        var samples: [UInt32] = [.max, 0, 1, 2, 3]
        let generated = try TransferPhrase.generate {
            try XCTUnwrap(samples.isEmpty ? nil : samples.removeFirst())
        }
        XCTAssertEqual(generated, TransferWords.words.prefix(4).joined(separator: " "))
        XCTAssertEqual(generated.split(separator: " ").count, 4)
        XCTAssertEqual(try TransferPhrase.normalized(generated), generated)
        XCTAssertTrue(samples.isEmpty)
        let repeated = try TransferPhrase.generate { 0 }
        XCTAssertEqual(repeated, Array(repeating: TransferWords.words[0], count: 4).joined(separator: " "))
    }

    func testRandomSourceFailurePropagatesWithoutAnInsecureFallback() {
        enum RandomFailure: Error { case unavailable }
        XCTAssertThrowsError(try TransferPhrase.generate { throw RandomFailure.unavailable }) { error in
            guard case RandomFailure.unavailable = error else { return XCTFail("The random-source failure must propagate.") }
        }
    }

    func testFixedPBKDF2SHA256KeyMatchesIndependentPythonVector() throws {
        // hashlib.pbkdf2_hmac('sha256', phrase, fixed v2 info + bytes(1...16), 600000, 32).
        let salt = Data((1...16).map(UInt8.init))
        let key = try RoomTransfer.phraseKeyData(code: phrase, salt: salt)
        XCTAssertEqual(key.map { String(format: "%02x", $0) }.joined(), "0adfde5ec0498154d3b04e4bcaeb8c314f2b1868afa868bdf4f26eb55f241b1b")
        XCTAssertEqual(try RoomTransfer.phraseKeyData(code: "CABLE-LUNAR-VELVET-WALNUT", salt: salt), key)
        XCTAssertNotEqual(try RoomTransfer.phraseKeyData(code: "walnut velvet lunar cable", salt: salt), key)
        XCTAssertNotEqual(try RoomTransfer.phraseKeyData(code: phrase, salt: Data(repeating: 1, count: 16)), key)
        XCTAssertThrowsError(try RoomTransfer.phraseKeyData(code: phrase, salt: Data()))
    }
}
