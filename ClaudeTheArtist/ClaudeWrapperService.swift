//
//  ClaudeWrapperService.swift
//  ClaudeTheArtist
//
//  Service to manage the Claude wrapper subprocess and handle stdin/stdout communication
//

import Foundation

/// Message received from the Claude wrapper
struct WrapperMessage: Codable, Identifiable {
    let id = UUID()
    let type: String
    let messageType: String?
    let content: [MessageContent]?
    let data: String?
    let command: String?
    let success: Bool?
    let error: String?
    let toolUseId: String?
    let name: String?
    let input: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type
        case messageType = "message_type"
        case content
        case data
        case command
        case success
        case error
        case toolUseId = "tool_use_id"
        case name
        case input
    }
}

struct MessageContent: Codable {
    let type: String
    let text: String?
}

/// Helper to decode Any JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let arrayValue = value as? [Any] {
            try container.encode(arrayValue.map { AnyCodable($0) })
        } else if let dictValue = value as? [String: Any] {
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }
}

/// Observable service that manages the Claude wrapper subprocess
@MainActor
@Observable
class ClaudeWrapperService {
    var messages: [ChatMessage] = []
    var isConnected = false
    var error: String?
    var canvasModel = PixelCanvasModel()

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var outputTask: Task<Void, Never>?

    /// Start the wrapper subprocess and connect to Claude
    func start() async {
        guard process == nil else {
            print("Service already started")
            return
        }

        // Find the project root (go up from ClaudeTheArtist directory)
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // ClaudeTheArtist
            .deletingLastPathComponent()  // ClaudeSDKDemo

        let wrapperPath = projectRoot.appendingPathComponent("claude_sdk_wrapper.py")
        let uvPath = URL(fileURLWithPath: "/Users/skrul/.local/bin/uv")

        print("Starting wrapper at: \(wrapperPath.path)")
        print("Using uv at: \(uvPath.path)")
        print("Working directory: \(projectRoot.path)")

        // Create pipes for communication
        inputPipe = Pipe()
        outputPipe = Pipe()

        // Setup process - use uv run which handles venv setup automatically
        process = Process()
        process?.executableURL = uvPath
        process?.arguments = ["run", wrapperPath.path]
        process?.currentDirectoryURL = projectRoot
        process?.standardInput = inputPipe
        process?.standardOutput = outputPipe
        process?.standardError = outputPipe  // Merge stderr to stdout

        // Set up environment
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process?.environment = environment

        do {

            try process?.run()
            isConnected = true

            // Start reading output
            startReadingOutput()

            // Wait a moment for process to start
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Define the draw_pixel tool
            let tools: [[String: Any]] = [
                [
                    "name": "draw_pixel",
                    "description": "Draw a single pixel on the 128x128 canvas at the given coordinates with the specified color",
                    "input_schema": [
                        "type": "object",
                        "properties": [
                            "x": [
                                "type": "integer",
                                "description": "X coordinate (0-127)"
                            ],
                            "y": [
                                "type": "integer",
                                "description": "Y coordinate (0-127)"
                            ],
                            "color": [
                                "type": "string",
                                "description": "Hex color code (e.g., '#FF0000' for red)"
                            ]
                        ],
                        "required": ["x", "y", "color"]
                    ]
                ]
            ]

            // Send create_client command with tools
            try await sendCommand([
                "command": "create_client",
                "tools": tools
            ])

            // Add system message
            messages.append(ChatMessage(
                role: .system,
                text: "Connected to Claude",
                timestamp: Date()
            ))
        } catch {
            let errorMsg = "Failed to start wrapper: \(error.localizedDescription)"
            self.error = errorMsg
            print(errorMsg)
            messages.append(ChatMessage(
                role: .system,
                text: errorMsg,
                timestamp: Date()
            ))
        }
    }

    /// Stop the wrapper subprocess
    func stop() {
        outputTask?.cancel()
        outputTask = nil

        if let process = process, process.isRunning {
            // Try to send disconnect command gracefully
            Task {
                try? await sendCommand(["command": "disconnect"])
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                process.terminate()
            }
        }

        inputPipe = nil
        outputPipe = nil
        process = nil
        isConnected = false

        messages.append(ChatMessage(
            role: .system,
            text: "Disconnected from Claude",
            timestamp: Date()
        ))
    }

    /// Send a query to Claude
    func sendQuery(_ prompt: String) async throws {
        guard isConnected else {
            throw NSError(domain: "ClaudeWrapper", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Not connected"
            ])
        }

        // Add user message to chat
        messages.append(ChatMessage(
            role: .user,
            text: prompt,
            timestamp: Date()
        ))

        // Send query command
        try await sendCommand([
            "command": "query",
            "prompt": prompt
        ])
    }

    // MARK: - Private Methods

    private func sendCommand(_ command: [String: Any]) async throws {
        guard let inputPipe = inputPipe else {
            throw NSError(domain: "ClaudeWrapper", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Input pipe not available"
            ])
        }

        let jsonData = try JSONSerialization.data(withJSONObject: command)
        var dataWithNewline = jsonData
        dataWithNewline.append(contentsOf: [0x0A]) // Add newline

        try inputPipe.fileHandleForWriting.write(contentsOf: dataWithNewline)
    }

    private func startReadingOutput() {
        guard let outputPipe = outputPipe else { return }

        outputTask = Task {
            let handle = outputPipe.fileHandleForReading

            while !Task.isCancelled {
                // Read a line from stdout
                guard let line = try? await handle.readLine() else {
                    break
                }

                // Parse JSON
                guard let data = line.data(using: .utf8) else { continue }

                do {
                    let decoder = JSONDecoder()
                    let message = try decoder.decode(WrapperMessage.self, from: data)
                    await handleWrapperMessage(message)
                } catch {
                    print("Failed to decode message: \(error)")
                    print("Raw line: \(line)")
                }
            }

            print("Output reading task ended")
        }
    }

    private func handleWrapperMessage(_ message: WrapperMessage) {
        switch message.type {
        case "message":
            if message.messageType == "AssistantMessage", let content = message.content {
                // Extract text from assistant message
                let text = content.compactMap { $0.text }.joined(separator: "\n")
                if !text.isEmpty {
                    messages.append(ChatMessage(
                        role: .assistant,
                        text: text,
                        timestamp: Date()
                    ))
                }
            }
            // Ignore other message types (SystemMessage, ResultMessage)

        case "response":
            // Command responses - log but don't show in chat
            print("Command '\(message.command ?? "unknown")' succeeded")

        case "error":
            // Show errors in chat
            let errorText = message.error ?? "Unknown error"
            messages.append(ChatMessage(
                role: .system,
                text: "Error: \(errorText)",
                timestamp: Date()
            ))

        case "tool_invocation":
            // Handle tool invocations
            guard let toolUseId = message.toolUseId,
                  let toolName = message.name,
                  let input = message.input else {
                print("Invalid tool invocation message")
                return
            }

            print("Tool invocation: \(toolName) with ID: \(toolUseId)")
            handleToolInvocation(toolUseId: toolUseId, toolName: toolName, input: input)

        default:
            print("Unknown message type: \(message.type)")
        }
    }

    private func handleToolInvocation(toolUseId: String, toolName: String, input: [String: AnyCodable]) {
        Task {
            var result: String
            var isError = false

            switch toolName {
            case "draw_pixel":
                // Extract parameters
                guard let x = input["x"]?.value as? Int,
                      let y = input["y"]?.value as? Int,
                      let colorString = input["color"]?.value as? String else {
                    result = "Invalid parameters for draw_pixel"
                    isError = true
                    await sendToolResult(toolUseId: toolUseId, content: result, isError: isError)
                    return
                }

                // Parse color
                guard let color = canvasModel.parseColor(colorString) else {
                    result = "Invalid color format: \(colorString). Use hex format like #FF0000"
                    isError = true
                    await sendToolResult(toolUseId: toolUseId, content: result, isError: isError)
                    return
                }

                // Draw pixel
                canvasModel.setPixel(x: x, y: y, color: color)
                result = "Drew pixel at (\(x), \(y)) with color \(colorString)"

            default:
                result = "Unknown tool: \(toolName)"
                isError = true
            }

            // Send result back to Python wrapper
            await sendToolResult(toolUseId: toolUseId, content: result, isError: isError)
        }
    }

    private func sendToolResult(toolUseId: String, content: String, isError: Bool) async {
        do {
            try await sendCommand([
                "command": "tool_result",
                "tool_use_id": toolUseId,
                "content": content,
                "is_error": isError
            ])
        } catch {
            print("Failed to send tool result: \(error)")
        }
    }
}

// MARK: - Helper Extensions

extension FileHandle {
    /// Read a line from the file handle asynchronously
    func readLine() async throws -> String? {
        var lineData = Data()
        let bufferSize = 1

        while true {
            let data = try await bytes(from: self, count: bufferSize)

            if data.isEmpty {
                // EOF
                if lineData.isEmpty {
                    return nil
                } else {
                    return String(data: lineData, encoding: .utf8)
                }
            }

            if data.first == 0x0A { // newline
                return String(data: lineData, encoding: .utf8)
            }

            lineData.append(contentsOf: data)
        }
    }

    private func bytes(from handle: FileHandle, count: Int) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = handle.readData(ofLength: count)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date

    enum Role {
        case user
        case assistant
        case system
    }
}
