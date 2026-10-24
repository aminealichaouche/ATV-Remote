// swift-tools-version: 6.2
// Runtime-only local manifest. Copyright Apple Inc.; see LICENSE.txt.
import PackageDescription
let package = Package(
    name: "SwiftProtobuf",
    products: [.library(name: "SwiftProtobuf", targets: ["SwiftProtobuf"])],
    traits: [
        .trait(name: "BinaryDelimitedStreams", description: "Binary stream APIs."),
        .trait(name: "FieldMaskUtilities", description: "Field mask support."),
        .default(enabledTraits: ["BinaryDelimitedStreams", "FieldMaskUtilities"])
    ],
    targets: [.target(name: "SwiftProtobuf", exclude: ["CMakeLists.txt"], resources: [.copy("PrivacyInfo.xcprivacy")])]
)
