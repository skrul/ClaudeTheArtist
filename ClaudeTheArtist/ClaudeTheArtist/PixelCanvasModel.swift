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

    /// Parse a hex color string (e.g., "#FF0000" or "FF0000") to Color
    func parseColor(_ colorString: String) -> Color? {
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
