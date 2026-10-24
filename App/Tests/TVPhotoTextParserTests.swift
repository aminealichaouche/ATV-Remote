import XCTest
@testable import RoomRemote

final class TVPhotoTextParserTests: XCTestCase {
    func testAboutTVExtractsLabeledNetworkAdaptersAndModelCode() {
        let result = TVPhotoTextParser.parse(lines: ["About TV", "Model Code: QN55S95BAFXZA", "Serial Number: 00123456789A",
            "Wireless MAC Address: 00:12:34:56:78:9a", "Wired MAC Address: 02-AA-BB-CC-DD-EE", "IP Address: 192.168.50.168"])
        XCTAssertEqual(result.ipAddresses, ["192.168.50.168"])
        XCTAssertEqual(result.macAddresses, [mac("00:12:34:56:78:9A", .wireless), mac("02:AA:BB:CC:DD:EE", .wired)])
        XCTAssertEqual(result.modelName, "QN55S95BAFXZA")
    }

    func testImmediateNextRowsWorkWithoutLeakingAcrossAlternatingAdapterLabels() {
        let result = TVPhotoTextParser.parse(lines: ["Wireless MAC Address", "00:12:34:56:78:9A", "Wired MAC Address", "02:AA:BB:CC:DD:EE",
            "IPv4 Address", "10.10.5.8", "Model Number", "UN50TU7000FXZA"])
        XCTAssertEqual(result.macAddresses, [mac("00:12:34:56:78:9A", .wireless), mac("02:AA:BB:CC:DD:EE", .wired)])
        XCTAssertEqual(result.ipAddresses, ["10.10.5.8"])
        XCTAssertEqual(result.modelName, "UN50TU7000FXZA")
    }

    func testSamePhysicalRowCanContainMultipleLabeledValues() {
        let result = TVPhotoTextParser.parse(lines: ["Wireless MAC Address: 00:12:34:56:78:9A | Wired MAC Address: 02:AA:BB:CC:DD:EE",
            "IP Address: 192.168.1.50 Gateway: 192.168.1.1 DNS Server: 192.168.1.2 Subnet Mask: 255.255.255.0"])
        XCTAssertEqual(result.macAddresses, [mac("00:12:34:56:78:9A", .wireless), mac("02:AA:BB:CC:DD:EE", .wired)])
        XCTAssertEqual(result.ipAddresses, ["192.168.1.50"])
    }

    func testGatewayDNSSubnetAndPublicAddressesCannotBecomeTVIP() {
        let result = TVPhotoTextParser.parse(lines: ["Gateway: 192.168.1.1", "Default Gateway", "10.0.0.1", "DNS Server: 192.168.1.2",
            "IP Address", "Gateway: 192.168.1.1", "192.168.1.3", "Public IP Address: 192.168.1.7", "External IP Address: 10.0.0.2",
            "Internet IP Address: 172.16.1.3", "Router IP Address: 192.168.1.8", "Subnet Mask: 255.255.255.0", "IP Address: 8.8.8.8",
            "DNS IP Address: 192.168.1.2", "DNS Server IP Address: 192.168.1.2", "Gateway IP: 192.168.1.1",
            "Subnet IP Address: 192.168.1.9", "Bluetooth IP Address: 192.168.1.10"])
        XCTAssertTrue(result.ipAddresses.isEmpty)
    }

    func testNoUnlabeledAddressesSerialNumbersOrPairingHashesAreGuessed() {
        let result = TVPhotoTextParser.parse(lines: ["192.168.1.50", "00:12:34:56:78:9A", "00123456789A",
            "Serial Number: 00123456789A", "Device ID: 00123456789A", "Pairing Code: 00123456789A"])
        XCTAssertEqual(result, TVPhotoScanResult(ipAddresses: [], macAddresses: [], modelName: nil))
    }

    func testBluetoothRemoteAndOtherDeviceMACsAreExcludedBeforeGenericLabel() {
        let result = TVPhotoTextParser.parse(lines: ["Bluetooth MAC Address: 00:12:34:56:78:9A", "BT Address", "02:AA:BB:CC:DD:EE",
            "Remote Control MAC Address: 04:AA:BB:CC:DD:EE", "MAC Address (Bluetooth): 06:AA:BB:CC:DD:EE",
            "Phone MAC Address: 08:AA:BB:CC:DD:EE", "Router MAC Address: 0A:AA:BB:CC:DD:EE", "MAC Address: remote 0C:AA:BB:CC:DD:EE",
            "Gateway MAC Address: 0E:AA:BB:CC:DD:EE", "Bluetooth Device MAC Address: 10:AA:BB:CC:DD:EE",
            "Remote Device MAC Address: 12:AA:BB:CC:DD:EE", "Smart Control MAC Address: 14:AA:BB:CC:DD:EE"])
        XCTAssertTrue(result.macAddresses.isEmpty)
    }

    func testGenericTVMACRequiresLabelAndAdapterSuffixesAreRecognized() {
        let result = TVPhotoTextParser.parse(lines: ["TV MAC Address: 0012.3456.789a", "mac address (wi-fi): 02aabbccddee",
            "MAC Address (Ethernet): 04:AA:BB:CC:DD:EE"])
        XCTAssertEqual(result.macAddresses, [mac("00:12:34:56:78:9A", .unspecified), mac("02:AA:BB:CC:DD:EE", .wireless), mac("04:AA:BB:CC:DD:EE", .wired)])
    }

    func testCaseAndWhitespaceVaryWithoutChangingHexCharacters() {
        let result = TVPhotoTextParser.parse(lines: ["  wI Fi\tMaC\tAdDrEsS : 00-12-34-56-78-9a  ", " ipv4\tADDRESS = 169.254.10.20 "])
        XCTAssertEqual(result.macAddresses, [mac("00:12:34:56:78:9A", .wireless)])
        XCTAssertEqual(result.ipAddresses, ["169.254.10.20"])
    }

    func testMalformedAndNonUnicastMACValuesDoNotGetRepairedOrPartiallyMatched() {
        let invalid = ["00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF", "01:12:34:56:78:9A", "00:12:34:56:78:9AA",
            "00:12:34:56:78:9A:BC", "0O:12:34:56:78:9A", "00:12:34:56:78:9G", "00:12-34:56:78:9A",
            "00 12 34 56 78 9A", "00123456789AB", "X00123456789A", "００123456789A", "0012.3456.789A.1234",
            "https://example.com/?mac=00123456789A", "example.com?mac=00123456789A", "Ａ00123456789A"]
        for value in invalid {
            XCTAssertTrue(TVPhotoTextParser.parse(lines: ["MAC Address: " + value]).macAddresses.isEmpty, "Accepted \(value)")
        }
    }

    func testIPValidationRejectsPublicMalformedBroadcastURLsAndPortFragments() {
        let invalid = ["8.8.8.8", "127.0.0.1", "255.255.255.255", "192.168.1.255", "192.168.01.50", "192.168.1.300",
            "172.15.1.1", "172.32.1.1", "192.168.1.5O", "https://192.168.1.50", "192.168.1.50:8002", "192.168.1.50/24",
            "fd00::192.168.1.50", "x192.168.1.50", "192.168.1.50.6", "https://example.com/?ip=192.168.1.50",
            "https://example.com/?IPv4=192.168.1.50", "example.com?ip=192.168.1.50", "www.example.com/IP=192.168.1.50",
            "https://example.com/IP Address: 192.168.1.50", "Ａ192.168.1.50"]
        for value in invalid {
            XCTAssertTrue(TVPhotoTextParser.parse(lines: ["IP Address: " + value]).ipAddresses.isEmpty, "Accepted \(value)")
        }
    }

    func testMultipleTVAddressCandidatesRemainDistinctAndInReadOrder() {
        let result = TVPhotoTextParser.parse(lines: ["IP Address: 192.168.1.50", "IP Address: 10.0.0.20", "IP Address: 192.168.1.50",
            "Wireless MAC Address: 00:12:34:56:78:9A", "Wireless MAC Address: 02:AA:BB:CC:DD:EE"])
        XCTAssertEqual(result.ipAddresses, ["192.168.1.50", "10.0.0.20"])
        XCTAssertEqual(result.macAddresses, [mac("00:12:34:56:78:9A", .wireless), mac("02:AA:BB:CC:DD:EE", .wireless)])
    }

    func testKnownInterfaceCoalescesGenericDuplicatesButDoesNotMergeDifferentAdapters() {
        let result = TVPhotoTextParser.parse(lines: ["MAC Address: 00123456789A", "Wireless MAC Address: 00:12:34:56:78:9A",
            "MAC Address: 00-12-34-56-78-9A", "Wired MAC Address: 00:12:34:56:78:9A", "Wireless MAC Address: 0012.3456.789A"])
        XCTAssertEqual(result.macAddresses, [mac("00:12:34:56:78:9A", .wireless), mac("00:12:34:56:78:9A", .wired)])
        XCTAssertNotEqual(result.macAddresses[0].id, result.macAddresses[1].id)
    }

    func testLabelCannotClaimAnAddressMoreThanOneRowLaterOrBeyondBlankRow() {
        for lines in [["IP Address", "Connected", "192.168.1.50"], ["IP Address", "", "192.168.1.50"],
            ["MAC Address", "Unavailable", "00:12:34:56:78:9A"], ["MAC Address", "Serial Number", "00123456789A"]] {
            let result = TVPhotoTextParser.parse(lines: lines)
            XCTAssertTrue(result.ipAddresses.isEmpty)
            XCTAssertTrue(result.macAddresses.isEmpty)
        }
    }

    func testModelCodeDoesNotReadSerialOrUnboundedProseAndAmbiguityIsNotChosen() {
        XCTAssertNil(TVPhotoTextParser.parse(lines: ["Serial Number: QN55S95BAFXZA"]).modelName)
        XCTAssertNil(TVPhotoTextParser.parse(lines: ["Model Code: " + String(repeating: "A", count: 80) + "1"]).modelName)
        XCTAssertNil(TVPhotoTextParser.parse(lines: ["Model Code: Unknown"]).modelName)
        XCTAssertNil(TVPhotoTextParser.parse(lines: ["Model Code: QN55S95BAFXZA", "Model Number: UN50TU7000FXZA"]).modelName)
        XCTAssertEqual(TVPhotoTextParser.parse(lines: ["Model Code: QN55S95BAFXZA Serial Number: 00123456789A"]).modelName, "QN55S95BAFXZA")
    }

    func testInputBoundsRejectOversizedRowsWithoutTruncatingAddressAndLimitLineCount() {
        let long = "IP Address: 192.168.1.50" + String(repeating: " ", count: 400)
        XCTAssertTrue(TVPhotoTextParser.parse(lines: [long]).ipAddresses.isEmpty)
        let unicodeLong = String(repeating: "😀", count: 401) + " IP Address: 192.168.1.50"
        XCTAssertTrue(TVPhotoTextParser.parse(lines: [unicodeLong]).ipAddresses.isEmpty)
        XCTAssertTrue(TVPhotoTextParser.parse(lines: Array(repeating: "About TV", count: 200) + ["IP Address: 192.168.1.50"]).ipAddresses.isEmpty)
        let oversizedNextRow = TVPhotoTextParser.parse(lines: ["IP Address", String(repeating: " ", count: 401), "192.168.1.50"])
        XCTAssertTrue(oversizedNextRow.ipAddresses.isEmpty)
    }

    func testUTF8BudgetDoesNotReadAnAddressAfterTwentyThousandBytes() {
        let rows = Array(repeating: String(repeating: "😀", count: 250), count: 20)
        XCTAssertTrue(TVPhotoTextParser.parse(lines: rows + ["IP Address: 192.168.1.50"]).ipAddresses.isEmpty)
        let atBoundary = Array(repeating: String(repeating: "x", count: 400), count: 49) + ["IP Address: 192.168.1.50"]
        XCTAssertEqual(TVPhotoTextParser.parse(lines: atBoundary).ipAddresses, ["192.168.1.50"])
    }

    private func mac(_ address: String, _ interface: TVPhotoMACInterface) -> TVPhotoMACCandidate {
        TVPhotoMACCandidate(address: address, interface: interface)
    }
}
