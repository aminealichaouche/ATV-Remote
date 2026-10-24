import Foundation
import CoreTransferable
import UniformTypeIdentifiers
extension UTType {
    static let roomRemoteSetup = UTType(exportedAs: "local.roomremote.transfer", conformingTo: .data)
    static let roomRemoteDirectSetup = UTType(exportedAs: "io.github.atvremote.direct-setup", conformingTo: .data)
}

/// Explicit file types let iOS route an AirDrop into ATV Remote instead of
/// sharing a URL string. The visible ShareLink also enables proximity sharing.
struct SetupShareFile: Transferable, Sendable {
    let url: URL
    let requiresPhrase: Bool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .roomRemoteDirectSetup) { item in
            SentTransferredFile(item.url)
        }.exportingCondition { !$0.requiresPhrase }
        FileRepresentation(exportedContentType: .roomRemoteSetup) { item in
            SentTransferredFile(item.url)
        }.exportingCondition { $0.requiresPhrase }
    }
}
