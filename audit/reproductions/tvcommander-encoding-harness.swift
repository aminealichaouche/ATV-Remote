import Foundation
@main
struct Check {
    static func main() throws {
        let command = TVRemoteCommand.createClickCommand(.enter)
        print(try command.asString() ?? "encoding failed")
        let cfg = TVConnectionConfiguration(id:nil,app:"Remote",path:"/api/v2/channels/samsung.remote.control",ipAddress:"192.0.2.10",port:8002,scheme:"wss",token:"a&extra=1")
        print(cfg.wssURL()?.absoluteString ?? "URL failed")
        print("Invalid MAC packet length", Data.magicPacket(from:TVWakeOnLANDevice(mac:"bad")).count)
    }
}
