//
//  PixelCanvas.swift
//  ClaudeTheArtist
//
//  SwiftUI view for rendering the 128x128 pixel canvas
//

import SwiftUI

struct PixelCanvas: View {
    var model: PixelCanvasModel

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let pixelSize = size / CGFloat(PixelCanvasModel.gridSize)

            Canvas { context, canvasSize in
                let pixels = model.getAllPixels()

                for y in 0..<PixelCanvasModel.gridSize {
                    for x in 0..<PixelCanvasModel.gridSize {
                        let rect = CGRect(
                            x: CGFloat(x) * pixelSize,
                            y: CGFloat(y) * pixelSize,
                            width: pixelSize,
                            height: pixelSize
                        )

                        context.fill(
                            Path(rect),
                            with: .color(pixels[y][x])
                        )
                    }
                }
            }
            .frame(width: size, height: size)
            .border(Color.gray, width: 1)
        }
    }
}

#Preview {
    let model = PixelCanvasModel()

    // Draw some test pixels
    model.setPixel(x: 10, y: 10, color: .red)
    model.setPixel(x: 20, y: 20, color: .blue)
    model.setPixel(x: 30, y: 30, color: .green)

    return PixelCanvas(model: model)
        .frame(width: 512, height: 512)
}
