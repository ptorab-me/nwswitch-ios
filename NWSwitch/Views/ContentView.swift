//
//  ContentView.swift
//  NWSwitch
//
//  Created by Payam Torab on 6/7/23.
//

import SwiftUI

struct ContentView: View {
    // tcp echo clients
#if os(macOS) // Wi-Fi, Ethernet, any
    @StateObject private var client1 = Client(requiredInterfaceType: .wifi)
    @StateObject private var client2 = Client(requiredInterfaceType: .wiredEthernet)
    @StateObject private var client3 = Client(requiredInterfaceType: nil)
#else // Wi-Fi, cellular, any
    @StateObject private var client1 = Client(requiredInterfaceType: .wifi)
    @StateObject private var client2 = Client(requiredInterfaceType: .cellular)
    @StateObject private var client3 = Client(requiredInterfaceType: nil)
#endif
    
    var body: some View {
        VStack {
#if os(macOS) // Wi-Fi, Ethernet, any
            ClientView(client: client1, title: "Wi-Fi connection", image: "wifi", color: .blue)
            ClientView(client: client2, title: "Wired connection", image: "cable.connector.horizontal", color: .purple)
            ClientView(client: client3, title: "Any connection", image: "network", color: .gray)
#else // Wi-Fi, cellular, any
            ClientView(client: client1, title: "Wi-Fi connection", image: "wifi", color: .blue)
            ClientView(client: client2, title: "Cellular connection", image: "cellularbars", color: .green)
            ClientView(client: client3, title: "Any connection", image: "network", color: .gray)
#endif
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
