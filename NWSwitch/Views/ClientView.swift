//
//  ClientView.swift
//  NWSwitch
//
//  Created by Payam Torab on 6/7/23.
//

import SwiftUI

struct ClientView: View {
    @ObservedObject var client: Client
    
    let title: String
    let image: String
    let color: Color
    
    let logScrollLines = 64
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Section(header:
                Label(title + " " + client.connectionInfo, systemImage: image)
                    .foregroundColor(color)
                    .font(.system(size:15.0))
            ) {
                Divider()
                ScrollViewReader { scroller in
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(client.logBuffer.suffix(logScrollLines), id: \.id) { logLine in
                                Text(logLine.text)
                                    .font(.system(size: 15.0))
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.bottom)
                    .onChange(of: client.logBuffer.count) { _ in
                        if let last = client.logBuffer.last {
                            withAnimation {
                                scroller.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ClientView_Previews: PreviewProvider {
    static private var client = Client(requiredInterfaceType: .wifi)
    
    static var previews: some View {
        ClientView(client: client, title: "Wi-Fi only connection", image: "wifi", color: .blue)
    }
}
