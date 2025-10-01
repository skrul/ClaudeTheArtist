//
//  ContentView.swift
//  ClaudeTheArtist
//
//  Created by Steve Krulewitz on 9/30/25.
//

import SwiftUI

struct ContentView: View {
    @State private var service = ClaudeWrapperService()
    @State private var showingError = false
    @State private var showingSettings = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Chat panel (left third)
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Chat with Claude")
                            .font(.headline)
                        Spacer()
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.plain)
                        Circle()
                            .fill(service.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()

                    // Chat view
                    ChatView(service: service)
                }
                .frame(width: geometry.size.width / 3)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                // Canvas area (right two-thirds)
                VStack {
                    Text("Pixel Canvas (128x128)")
                        .font(.headline)
                        .padding(.top)

                    PixelCanvas(model: service.canvasModel)
                        .padding()

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .task {
            // Start the service when view appears
            await service.start()
        }
        .alert("Error", isPresented: $showingError, presenting: service.error) { _ in
            Button("OK") {
                service.error = nil
            }
        } message: { error in
            Text(error)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
