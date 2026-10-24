import XCTest
import Network
@testable import RoomRemote

final class SamsungWakeOnLANTests: XCTestCase {
    private func device(address: String = "192.168.1.50", mac: String? = "00:12:34:56:78:9A") -> RemoteDevice {
        var device = RemoteDevice(id: "living-samsung", kind: .samsung, name: "Living Room TV", address: address, port: 8002)
        device.wakeMACAddress = mac
        return device
    }

    func testAcceptedMACFormatsNormalizeToTheSameUnicastAddress() throws {
        for raw in ["00:12:34:56:78:9a", "  00-12-34-56-78-9A\n", "00123456789a", "0012.3456.789a"] {
            XCTAssertEqual(try SamsungWakeOnLAN.normalizedMAC(raw), "00:12:34:56:78:9A")
        }
        XCTAssertEqual(try SamsungWakeOnLAN.normalizedMAC("02:AA:BB:CC:DD:EE"), "02:AA:BB:CC:DD:EE", "Locally administered unicast addresses remain valid")
    }

    func testInvalidNonIndividualMACAddressesAreRejected() {
        for raw in ["", "00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF", "01:12:34:56:78:9A", "33:33:00:00:00:01", "00:12:34:56:78", "00:12:34:56:78:9AA", "0:12:34:56:78:9A", "00:12-34:56:78:9A", "00 12 34 56 78 9A", "００123456789A", "00:12:34:56:78:GG", "001.2345.6789A", "00:12:34:56:78:9A\nanything"] {
            XCTAssertThrowsError(try SamsungWakeOnLAN.normalizedMAC(raw), "Invalid MAC accepted: \(raw)")
        }
    }

    func testWakePacketContainsOnlyTheSyncBytesAndExactlySixteenTVAddresses() throws {
        let packet = try SamsungWakeOnLAN.packet(forMAC: "00:12:34:56:78:9A")
        let mac: [UInt8] = [0x00, 0x12, 0x34, 0x56, 0x78, 0x9A]
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(Array(packet.prefix(6)), Array(repeating: 0xFF, count: 6))
        for offset in stride(from: 6, to: 102, by: 6) {
            XCTAssertEqual(Array(packet[offset..<(offset + 6)]), mac)
        }
        XCTAssertThrowsError(try SamsungWakeOnLAN.packet(forMAC: "FF:FF:FF:FF:FF:FF"))
    }

    func testTargetUsesSavedPrivateIPv4AndFixedUDPPort() throws {
        let target = try SamsungWakeTarget(device: device(address: " 192.168.1.50\n"))
        XCTAssertEqual(target.deviceID, "living-samsung")
        XCTAssertEqual(target.address, "192.168.1.50")
        XCTAssertEqual(target.port, 9)
        XCTAssertEqual(target.macAddress, "00:12:34:56:78:9A")
        XCTAssertEqual(target.packetData, try SamsungWakeOnLAN.packet(forMAC: target.macAddress))
        for address in ["10.1.2.3", "172.16.2.3", "172.31.2.3", "169.254.10.1"] {
            XCTAssertEqual(try SamsungWakeTarget(device: device(address: address)).address, address)
        }
    }

    func testWakeCannotUseOtherKindsMissingMACOrUnsafeEndpoints() {
        for address in ["8.8.8.8", "127.0.0.1", "0.0.0.0", "224.0.0.1", "255.255.255.255", "192.168.1.255", "192.168.01.2", "192.168.1.300", "172.15.0.1", "172.32.0.1", "tv.local", "fd00::1234", "fd00::192.168.1.50", "::ffff:192.168.1.2", "https://192.168.1.50", "192.168.1.50/anything"] {
            XCTAssertThrowsError(try SamsungWakeTarget(device: device(address: address)), "Unsafe wake endpoint accepted: \(address)")
        }
        XCTAssertThrowsError(try SamsungWakeTarget(device: device(mac: nil)))
        XCTAssertThrowsError(try SamsungWakeTarget(device: device(mac: " \n")))
        var apple = device()
        apple.kind = .appleTV
        XCTAssertThrowsError(try SamsungWakeTarget(device: apple))
        var insecure = device()
        insecure.port = 8001
        XCTAssertThrowsError(try SamsungWakeTarget(device: insecure))
        var defaultPort = device()
        defaultPort.port = nil
        XCTAssertNoThrow(try SamsungWakeTarget(device: defaultPort))
    }

    func testCapturedTargetMustStillMatchItsSavedDeviceAndNetworkInterface() throws {
        let original = device()
        let target = try SamsungWakeTarget(device: original)
        XCTAssertTrue(target.matches(original))
        var same = original
        same.name = "Renamed Room TV"
        same.wakeMACAddress = "0012.3456.789a"
        same.address = " 192.168.1.50\n"
        XCTAssertTrue(target.matches(same), "Display changes and equivalent formatting do not change the endpoint")
        for variant in 0..<5 {
            var changed = original
            switch variant {
            case 0: changed.id = "family-samsung"
            case 1: changed.address = "192.168.1.51"
            case 2: changed.wakeMACAddress = "00:12:34:56:78:9B"
            case 3: changed.wakeMACAddress = nil
            default: changed.kind = .appleTV
            }
            XCTAssertFalse(target.matches(changed))
        }
    }

    func testReadyCallbacksMaySendOnlyOnePacketAndConcurrentRequestsCannotReplaceIt() {
        var gate = SamsungWakeSendGate()
        let first = UUID(), second = UUID()
        XCTAssertTrue(gate.begin(first))
        XCTAssertFalse(gate.begin(second))
        XCTAssertFalse(gate.ready(second))
        XCTAssertTrue(gate.ready(first))
        XCTAssertFalse(gate.ready(first), "Repeated ready callbacks cannot send a second datagram")
        XCTAssertFalse(gate.finish(second))
        XCTAssertEqual(gate.operationID, first)
        XCTAssertTrue(gate.finish(first))
        XCTAssertNil(gate.operationID)
        XCTAssertFalse(gate.isSending)
    }

    func testLateCompletionOrCancellationCannotFinishANewerWakeRequest() {
        var gate = SamsungWakeSendGate()
        let cancelled = UUID(), current = UUID()
        XCTAssertTrue(gate.begin(cancelled))
        XCTAssertTrue(gate.finish(cancelled), "Cancellation may finish before the transport is ready")
        XCTAssertTrue(gate.begin(current))
        XCTAssertFalse(gate.ready(cancelled))
        XCTAssertFalse(gate.finish(cancelled))
        XCTAssertEqual(gate.operationID, current)
        XCTAssertTrue(gate.ready(current))
        XCTAssertTrue(gate.finish(current))
        XCTAssertFalse(gate.finish(current), "Completion is one shot")
    }

    func testAlreadyCancelledRequestIsRejectedBeforeOpeningTransport() async throws {
        let sender = SamsungWakeSender()
        let target = try SamsungWakeTarget(device: device())
        let request = Task {
            // Cancellation is set inside this same task before the actor call,
            // so this test cannot race with opening or sending on a real socket.
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await sender.send(to: target)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        let rejectedAsCancellation = await request.value
        XCTAssertTrue(rejectedAsCancellation)
    }

    private func subnet(address: String = "192.168.1.10", mask: String? = "255.255.255.0", name: String = "en0",
        isUp: Bool = true, supportsBroadcast: Bool = true, isLoopback: Bool = false) -> SamsungWakeLocalSubnet {
        SamsungWakeLocalSubnet(interfaceName: name, address: address, netmask: mask,
            isUp: isUp, supportsBroadcast: supportsBroadcast, isLoopback: isLoopback)
    }

    func testSubnetBoundariesUseTheActualPrefixInsteadOfTheLastOctet() throws {
        let lower25 = subnet(mask: "255.255.255.128")
        XCTAssertEqual(try SamsungWakeLocalSubnet.source(for: "192.168.1.126", among: [lower25]).address, "192.168.1.10")
        for target in ["192.168.1.0", "192.168.1.127", "192.168.1.128"] {
            XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: target, among: [lower25]))
        }
        let middle26 = subnet(address: "192.168.1.130", mask: "255.255.255.192")
        XCTAssertNoThrow(try SamsungWakeLocalSubnet.source(for: "192.168.1.129", among: [middle26]))
        for target in ["192.168.1.128", "192.168.1.191", "192.168.1.192"] {
            XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: target, among: [middle26]))
        }
        let wider23 = subnet(address: "192.168.0.10", mask: "255.255.254.0")
        XCTAssertNoThrow(try SamsungWakeTarget(device: device(address: "192.168.1.0")), "An ending .0 can be an individual host on a /23")
        XCTAssertEqual(try SamsungWakeLocalSubnet.source(for: "192.168.1.0", among: [wider23]).address, "192.168.0.10")
        for target in ["192.168.0.0", "192.168.1.255", "192.168.2.1"] {
            XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: target, among: [wider23]))
        }
    }

    func testSubnetMasksMustBePresentContiguousAndHaveAnIndividualHostRange() {
        let masks: [String?] = [nil, "", "255.0.255.0", "255.255.255.254", "255.255.255.255", "0.0.0.0", "255.255.255.012", "fd00::"]
        for mask in masks {
            XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: "192.168.1.50", among: [subnet(mask: mask)]))
        }
        for localAddress in ["192.168.1.0", "192.168.1.255", "192.168.01.10", "fd00::1234", ""] {
            XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: "192.168.1.50", among: [subnet(address: localAddress)]))
        }
        XCTAssertNoThrow(try SamsungWakeLocalSubnet.source(for: "10.1.2.3", among: [subnet(address: "10.0.0.2", mask: "128.0.0.0")]))
        XCTAssertNoThrow(try SamsungWakeLocalSubnet.source(for: "192.168.1.9", among: [subnet(mask: "255.255.255.252")]))
        XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: "192.168.1.11", among: [subnet(mask: "255.255.255.252")]))
    }

    func testOnlyActiveBroadcastCapableNonLoopbackNonCellularInterfacesAreEligible() {
        let ineligible = [subnet(isUp: false), subnet(supportsBroadcast: false), subnet(isLoopback: true),
            subnet(name: "pdp_ip0"), subnet(name: ""), subnet(name: "utun4", supportsBroadcast: false)]
        for interface in ineligible {
            XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: "192.168.1.50", among: [interface]))
        }
        XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: "192.168.1.50", among: []))
        XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: "192.168.2.50", among: [subnet()]))
        XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: "192.168.1.10", among: [subnet()]), "This iPhone cannot be its own TV wake target")
    }

    func testMatchingSourceAllowsEthernetAndFailsClosedForOverlappingBroadcastRanges() throws {
        let wifi = subnet()
        let ethernet = subnet(address: "192.168.2.10", name: "en7")
        XCTAssertEqual(try SamsungWakeLocalSubnet.source(for: "192.168.2.50", among: [wifi, ethernet]),
            SamsungWakeLocalEndpoint(interfaceName: "en7", address: "192.168.2.10"))
        let moreSpecific = subnet(address: "192.168.1.130", mask: "255.255.255.128", name: "en7")
        XCTAssertEqual(try SamsungWakeLocalSubnet.source(for: "192.168.1.160", among: [wifi, moreSpecific]).interfaceName, "en7")
        let lower25 = subnet(mask: "255.255.255.128", name: "en7")
        XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: "192.168.1.127", among: [wifi, lower25]),
            "A wider overlapping subnet cannot bypass another active interface's directed-broadcast boundary")
        XCTAssertThrowsError(try SamsungWakeLocalSubnet.source(for: "192.168.1.130", among: [wifi, moreSpecific]),
            "A local address on another matching interface must still be rejected")
    }

    func testActualUDPParametersBindTheCheckedSourceAndProhibitCellular() throws {
        let source = try SamsungWakeLocalSubnet.source(for: "192.168.2.50",
            among: [subnet(address: "192.168.2.10", name: "en7")])
        let parameters = SamsungWakeOnLAN.parameters(for: source)
        XCTAssertFalse(parameters.includePeerToPeer)
        XCTAssertTrue(parameters.prohibitedInterfaceTypes?.contains(.cellular) == true)
        XCTAssertEqual(parameters.requiredInterfaceType, .other, "Wi-Fi-only routing must not exclude an iPhone Ethernet adapter")
        XCTAssertNil(parameters.requiredInterface)
        XCTAssertEqual(parameters.requiredLocalEndpoint, .hostPort(host: NWEndpoint.Host("192.168.2.10"), port: .any))
        XCTAssertNotNil(parameters.defaultProtocolStack.transportProtocol as? NWProtocolUDP.Options)
    }
}
