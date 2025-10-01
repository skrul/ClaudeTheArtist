//
//  PixelCanvasModel.swift
//  ClaudeTheArtist
//
//  Pixel canvas model for 128x128 grid
//

import Foundation
import SwiftUI

@MainActor
@Observable
class PixelCanvasModel {
    static let gridSize = 128

    // Store pixels as a flat array for performance
    private var pixels: [[Color]]

    init() {
        // Initialize with white pixels
        pixels = Array(repeating: Array(repeating: .white, count: Self.gridSize), count: Self.gridSize)
    }

    /// Get the color at a specific coordinate
    func getPixel(x: Int, y: Int) -> Color {
        guard x >= 0 && x < Self.gridSize && y >= 0 && y < Self.gridSize else {
            return .white
        }
        return pixels[y][x]
    }

    /// Set a pixel at specific coordinates
    func setPixel(x: Int, y: Int, color: Color) {
        guard x >= 0 && x < Self.gridSize && y >= 0 && y < Self.gridSize else {
            return
        }
        pixels[y][x] = color
    }

    /// Parse a color string (hex like "#FF0000" or name like "red") to Color
    func parseColor(_ colorString: String) -> Color? {
        let trimmed = colorString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Try color names first
        switch trimmed {
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "black": return .black
        case "white": return .white
        case "gray", "grey": return .gray
        case "cyan": return .cyan
        case "magenta": return Color(red: 1, green: 0, blue: 1)
        default: break
        }

        // Try hex parsing
        var hexString = colorString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove # if present
        if hexString.hasPrefix("#") {
            hexString.remove(at: hexString.startIndex)
        }

        // Must be 6 characters (RGB)
        guard hexString.count == 6 else {
            return nil
        }

        // Parse hex values
        var rgb: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&rgb) else {
            return nil
        }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
    }

    /// Clear the entire canvas
    func clear() {
        pixels = Array(repeating: Array(repeating: .white, count: Self.gridSize), count: Self.gridSize)
    }

    /// Get all pixels (for rendering)
    func getAllPixels() -> [[Color]] {
        return pixels
    }
}
