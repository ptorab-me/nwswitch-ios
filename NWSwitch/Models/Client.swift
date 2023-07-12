//
//  Client.swift
//  NWSwitch
//
//  Created by Payam Torab on 6/7/23.
//

import Foundation
import Network
import NetworkExtension
import CoreLocation

#if os(macOS)
import CoreWLAN
#endif

let host = NWEndpoint.Host("tcpbin.com")
let port = NWEndpoint.Port(rawValue: 4242)!

@available(iOS 14.0, *)
class Client: ObservableObject {
    @Published var connectionInfo: String = "\n"
    @Published var logBuffer: [LogLine] = []
    
    let requiredInterfaceType: NWInterface.InterfaceType?
    let dispatchQueue: DispatchQueue = DispatchQueue(label: "Client connection events")
    let locationManager = CLLocationManager()  // for Wi-Fi bssid and Country Code
    let logBufferSize = 256
    
    private var nwParameters: NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionDropTime = 3  // to quickly show connectivity changes
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        if (requiredInterfaceType != nil) {
            parameters.requiredInterfaceType = requiredInterfaceType!
        }
        return parameters
    }
    private var connection: NWConnection = NWConnection(host: host, port: port, using: .tcp)
    private var pathMonitor: NWPathMonitor = NWPathMonitor()
    
    private var setupNewConnection: Bool = false
    
    let echoInterval: TimeInterval = 1.0 // transmit interval in seconds
    var echoMessage: String
    
    struct LogLine: Identifiable {
        let id: UUID
        let text: String
        
        init(_ text: String) {
            self.id = UUID()
            self.text = text
        }
    }
    
    private func log(_ logMessage: String) {
        let text : String = Date.now.formatted(date: .omitted, time: .standard) + " " + logMessage
        // can run synchronously without DispatchQueue if Thread.isMainThread is true,
        // simpler code to run async all the time
        DispatchQueue.main.async {
            self.logBuffer.append(LogLine(text))
            if self.logBuffer.count > self.logBufferSize {
                self.logBuffer.removeFirst(self.logBuffer.count - self.logBufferSize)
            }
        }
    }
    
    private func updateConnectionInfo() {
        switch requiredInterfaceType {
        case .wifi:
#if os(macOS)
            let ifc = CWWiFiClient.shared().interface()
            connectionInfo = (ifc == nil) ? "\n" : "| SSID: \(ifc!.ssid() ?? "")\n" +
            "BSSID: \(ifc!.bssid() ?? "00:00:00:00:00:00"), RSSI: \(ifc!.rssiValue()) dBm"
#else
            // returned rssi is always 0.0; see https://developer.apple.com/forums/thread/128844
            NEHotspotNetwork.fetchCurrent(completionHandler: { nw in
                self.connectionInfo = (nw == nil) ? "\n" :
                "| SSID: \(nw!.ssid)\nBSSID: \(nw!.bssid), RSSI (0.0-1.0): \(nw!.signalStrength)"
            })
#endif
        default: break
        }
    }
    
    init(requiredInterfaceType: NWInterface.InterfaceType?) {
        self.requiredInterfaceType = requiredInterfaceType
        
        // interface specific initializations
        switch requiredInterfaceType {
        case .wifi:
            echoMessage = "On Wi-Fi";
            locationManager.requestWhenInUseAuthorization() // for connected Wi-Fi info
        case .cellular:
            echoMessage = "On Cellular";
        case .wiredEthernet:
            echoMessage = "On wired Ethernet";
        default:
            echoMessage = "On one of them";
        }
        
        // first time connection
        connection = NWConnection(host: host, port: port, using: nwParameters)
        connection.stateUpdateHandler = stateUpdateHandler
        connection.start(queue: dispatchQueue)
        setupReceive()
        
        // path monitor
        pathMonitor = (requiredInterfaceType == nil) ? NWPathMonitor() :
            NWPathMonitor(requiredInterfaceType: requiredInterfaceType!)
        pathMonitor.pathUpdateHandler = pathUpdateHandler
        pathMonitor.start(queue: dispatchQueue)
        
        // echo timer
        Timer.scheduledTimer(withTimeInterval: echoInterval, repeats: true) { _ in self.echo() }.fire()
    }
    
    private func echo() {
        updateConnectionInfo()
        
        if setupNewConnection {
            // set up a new connection; ARC will clean out the old connection
            connection = NWConnection(host: host, port: port, using: nwParameters)
            connection.stateUpdateHandler = stateUpdateHandler
            connection.start(queue: dispatchQueue)
            setupReceive()
            setupNewConnection = false
        } else {
            switch connection.state {
            case .ready:
                let data: Data = (echoMessage + "\n").data(using: .utf8)! // carriage return to prompt echo response
                connection.send(content: data, completion: .contentProcessed( { error in
                    if let error = error {
                        self.log("send error: .\(error.localizedDescription)")
                    }
                }))
            case .waiting(let error):
                log("waiting; error: \(error.localizedDescription); NWSwitch: Calling restart()")
                connection.restart()
            case .failed(let error):
                log("failed; error: \(error.localizedDescription)]; NWSwitch: Calling cancel()")
                connection.cancel()
            case .cancelled:
                log("connection cancelled, setting up a new one")
                setupNewConnection = true
            default:
                print("---> connection state: \(connection.state)")
                break
            }
        }
    }
    
    private func setupReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { (data, _, isComplete, error) in
            if let data = data, !data.isEmpty {
                let message = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .newlines)
                self.log("echo: \(message)")  // outside main thread, .log will take care of it
            }
            if !isComplete {
                self.setupReceive()
            }
        }
    }
    
    private func stateUpdateHandler(state: NWConnection.State) {
        // can show connection state changes here, e.g.,
        // switch state {
        // case .waiting(let error), .failed(let error):
        //     print("state: \(state), error: \(error.localizedDescription)")
        // default:
        //     break
        // }
    }
    
    private func pathUpdateHandler(newPath: Network.NWPath) {
        guard requiredInterfaceType == nil else { return } // use for the "any" type connection
        
        // filter below should theoretically limit to interfaces that the "any" type connection
        // is using, but it returns .wifi as the only available interface after bringing
        // back Wi-Fi on top of cellular (i.e., after connection has been running on cellular),
        // which then leads to suggesting connection has switched to .wifi -- so either "any" type
        // connections can change interface on the fly, or usesInterfaceType() predicate has a
        // different meaning; ssame behavior with requiredInterfaceType not set or set to .other
        let availableInterfaces = newPath.availableInterfaces
        //.filter({newPath.usesInterfaceType($0.type)})  // not behaving as expected
        
        if availableInterfaces.count == 1 {
            switch (availableInterfaces.first!.type) {
            case .wifi:             echoMessage = "On Wi-Fi"
            case .cellular:         echoMessage = "On cellular"
            case .wiredEthernet:    echoMessage = "On wired Ethernet"
            default:                echoMessage = "On something else"
            }
        }
    }
}
