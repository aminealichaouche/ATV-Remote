import Foundation

// Runner substitutes __DECODE__ with the pinned library's decode entry point.
// Each malformed input runs in a separate process, so a trap is observable.
let variant = CommandLine.arguments[1]
let data: Data
switch variant {
case "normal": data = Data([0x41, 0x61])
case "largeLength": data = Data([0x94] + Array(repeating: 0xff, count: 8))
case "truncatedArray": data = Data([0xdf, 0x04])
case "trailingBytes": data = Data([0x04, 0x04])
default: fatalError("Unknown harness case")
}
do {
    let value = try __DECODE__(data)
    print("accepted: \(value)")
} catch {
    print("rejected: \(error)")
}
