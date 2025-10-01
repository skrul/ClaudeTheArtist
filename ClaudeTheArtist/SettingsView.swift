//
//  SettingsView.swift
//  ClaudeTheArtist
//
//  Settings view for authentication configuration
//

import SwiftUI

enum AuthMethod: String {
    case cliAuth = "Claude Code CLI"
    case apiKey = "API Key"
}

struct SettingsView: View {
    @AppStorage("authMethod") private var authMethod: String = AuthMethod.cliAuth.rawValue
    @AppStorage("anthropicApiKey") private var apiKey: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var showingSaved = false
    @State private var isCheckingAuth = false
    @State private var isAuthenticated = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Authentication Settings")
                .font(.title)
                .padding(.top)

            // Auth method picker
            VStack(alignment: .leading, spacing: 10) {
                Text("Authentication Method")
                    .font(.headline)

                Picker("Auth Method", selection: $authMethod) {
                    Text(AuthMethod.cliAuth.rawValue).tag(AuthMethod.cliAuth.rawValue)
                    Text(AuthMethod.apiKey.rawValue).tag(AuthMethod.apiKey.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal)

            // CLI Auth Status
            if authMethod == AuthMethod.cliAuth.rawValue {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Claude Code CLI Status:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if isCheckingAuth {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isAuthenticated ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(isAuthenticated ? "Authenticated" : "Not authenticated")
                                    .font(.subheadline)
                            }
                        }
                    }

                    if !isAuthenticated && !isCheckingAuth {
                        Text("Run 'claude login' in Terminal to authenticate")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // API Key input
            if authMethod == AuthMethod.apiKey.rawValue {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Anthropic API Key")
                        .font(.headline)

                    Text("Get your API key from console.anthropic.com")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    SecureField("sk-ant-api03-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal)
            }

            if showingSaved {
                Text("✓ Saved")
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    withAnimation {
                        showingSaved = true
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 550, height: 350)
        .task {
            if authMethod == AuthMethod.cliAuth.rawValue {
                await checkCLIAuth()
            }
        }
    }

    private func checkCLIAuth() async {
        isCheckingAuth = true
        defer { isCheckingAuth = false }

        // Test auth by trying to connect to Claude SDK
        let process = Process()
        let uvPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/ClaudeTheArtist/.uv/uv")

        process.executableURL = uvPath
        process.arguments = [
            "run", "python", "-c",
            """
            from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions
            import asyncio
            import os
            for key in ['ANTHROPIC_API_KEY', 'CLAUDE_API_KEY']:
                os.environ.pop(key, None)
            async def test():
                try:
                    client = ClaudeSDKClient(ClaudeAgentOptions())
                    await client.connect()
                    print('AUTHENTICATED')
                    await client.disconnect()
                except:
                    print('NOT_AUTHENTICATED')
            asyncio.run(test())
            """
        ]

        let projectPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Code/ClaudeTheArtist")
        process.currentDirectoryURL = projectPath

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            // Wait with timeout
            let timeout = DispatchTime.now() + .seconds(10)
            let semaphore = DispatchSemaphore(value: 0)

            DispatchQueue.global().async {
                process.waitUntilExit()
                semaphore.signal()
            }

            if semaphore.wait(timeout: timeout) != .timedOut {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8),
                   output.contains("AUTHENTICATED") {
                    isAuthenticated = true
                    return
                }
            }
        } catch {}

        isAuthenticated = false
    }
}
