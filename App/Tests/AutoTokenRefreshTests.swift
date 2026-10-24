import Foundation
import XCTest
@testable import RoomRemote

final class AutoTokenRefreshTests: XCTestCase {
    private struct Records: Sendable {
        let vault = KeychainVault()
        let prefix = "unit.auto-token.\(UUID().uuidString)"
        var tokenKey: String { prefix + ".token" }
        var certificateKey: String { prefix + ".certificate" }
        let token = Data("synthetic-old-token".utf8)
        let certificate = Data(repeating: 1, count: 32)
    }

    /// Uses only fresh, randomly named synthetic records and always removes
    /// them. No user pairing key is read, updated or deleted by these tests.
    private func withRecords(_ operation: (Records) async throws -> Void) async throws {
        let records = Records()
        do {
            try await records.vault.store(records.token, forKey: records.tokenKey)
            try await records.vault.store(records.certificate, forKey: records.certificateKey)
            try await operation(records)
            try await records.vault.delete(forKey: records.tokenKey)
            try await records.vault.delete(forKey: records.certificateKey)
        } catch {
            try? await records.vault.delete(forKey: records.tokenKey)
            try? await records.vault.delete(forKey: records.certificateKey)
            throw error
        }
    }

    func testMatchingWinnerRefreshesExistingTokenAndPreservesCertificate() async throws {
        try await withRecords { records in
            let fresh = Data("synthetic-fresh-token".utf8)
            let changed = try await records.vault.refreshExistingToken(fresh, forKey: records.tokenKey,
                expectedToken: records.token, certificateKey: records.certificateKey, expectedCertificate: records.certificate)
            let token = try await records.vault.data(forKey: records.tokenKey)
            let certificate = try await records.vault.data(forKey: records.certificateKey)
            XCTAssertTrue(changed)
            XCTAssertEqual(token, fresh)
            XCTAssertEqual(certificate, records.certificate)
        }
    }

    func testChangedTokenOrCertificateRejectsRefreshWithoutReplacingRecords() async throws {
        try await withRecords { records in
            let fresh = Data("synthetic-fresh-token".utf8)
            let wrongToken = try await records.vault.refreshExistingToken(fresh, forKey: records.tokenKey,
                expectedToken: Data("other".utf8), certificateKey: records.certificateKey, expectedCertificate: records.certificate)
            let wrongCertificate = try await records.vault.refreshExistingToken(fresh, forKey: records.tokenKey,
                expectedToken: records.token, certificateKey: records.certificateKey, expectedCertificate: Data(repeating: 2, count: 32))
            let token = try await records.vault.data(forKey: records.tokenKey)
            XCTAssertFalse(wrongToken)
            XCTAssertFalse(wrongCertificate)
            XCTAssertEqual(token, records.token)
        }
    }

    func testForgottenTokenOrCertificateCannotBeRecreatedByAutoWinner() async throws {
        try await withRecords { records in
            let fresh = Data("synthetic-fresh-token".utf8)
            try await records.vault.delete(forKey: records.tokenKey)
            let missingToken = try await records.vault.refreshExistingToken(fresh, forKey: records.tokenKey,
                expectedToken: records.token, certificateKey: records.certificateKey, expectedCertificate: records.certificate)
            let absentToken = try await records.vault.data(forKey: records.tokenKey)
            XCTAssertFalse(missingToken)
            XCTAssertNil(absentToken)
            try await records.vault.store(records.token, forKey: records.tokenKey)
            try await records.vault.delete(forKey: records.certificateKey)
            let missingCertificate = try await records.vault.refreshExistingToken(fresh, forKey: records.tokenKey,
                expectedToken: records.token, certificateKey: records.certificateKey, expectedCertificate: records.certificate)
            let token = try await records.vault.data(forKey: records.tokenKey)
            let absentCertificate = try await records.vault.data(forKey: records.certificateKey)
            XCTAssertFalse(missingCertificate)
            XCTAssertEqual(token, records.token)
            XCTAssertNil(absentCertificate)
        }
    }

    func testConcurrentRefreshesHaveOnlyOneWinner() async throws {
        try await withRecords { records in
            async let first = records.vault.refreshExistingToken(Data("first".utf8), forKey: records.tokenKey,
                expectedToken: records.token, certificateKey: records.certificateKey, expectedCertificate: records.certificate)
            async let second = records.vault.refreshExistingToken(Data("second".utf8), forKey: records.tokenKey,
                expectedToken: records.token, certificateKey: records.certificateKey, expectedCertificate: records.certificate)
            let results = try await [first, second]
            let stored = try await records.vault.data(forKey: records.tokenKey)
            XCTAssertEqual(results.filter { $0 }.count, 1)
            XCTAssertTrue(stored == Data("first".utf8) || stored == Data("second".utf8))
        }
    }
}
