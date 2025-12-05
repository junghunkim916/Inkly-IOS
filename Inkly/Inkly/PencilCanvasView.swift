import SwiftUI
import PencilKit

struct PencilCanvasView: UIViewRepresentable {
    @Binding var canvasRef: PKCanvasView?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = false
        canvas.backgroundColor = .white
        DispatchQueue.main.async { self.canvasRef = canvas }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
