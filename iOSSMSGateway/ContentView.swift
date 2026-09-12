//
//  ContentView.swift
//  iOSSMSGateway
//
//  Created by Papp Zoltán on 2026. 09. 10..
//

import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BLEServerManager()

    var body: some View {
        NavigationView {
            VStack(spacing: 25) {
                VStack(spacing: 8) {
                    Text("BLE SMS Gateway Szerver")
                        .font(.title2)
                        .bold()
                    
                    Text(bleManager.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Button(action: {
                    if bleManager.isAdvertising {
                        bleManager.stopAdvertising()
                    } else {
                        bleManager.startAdvertising()
                    }
                }) {
                    Text(bleManager.isAdvertising ? "Hirdetés Leállítása" : "Hirdetés Indítása")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(bleManager.isAdvertising ? Color.red : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Utoljára fogadott üzenet/adat:")
                        .font(.headline)
                    
                    ScrollView {
                        Text(bleManager.receivedData.isEmpty ? "Még nem érkezett adat..." : bleManager.receivedData)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .frame(maxHeight: 200)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Szerver")
        }
    }
}

#Preview {
    ContentView()
}
