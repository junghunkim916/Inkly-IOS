//
//  PracticeCanvas.swift
//  Inkly
//
//  Created by mac on 10/31/25.
//
import SwiftUI
import PencilKit

struct PracticeCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.isOpaque = false
        canvas.backgroundColor = .clear         // ✅ 배경 투명 (배경 이미지는 SwiftUI에서 깔림)
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false

        // 툴피커
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.keyWindow {
            let picker = PKToolPicker()
            picker.setVisible(true, forFirstResponder: canvas)
            picker.addObserver(canvas)
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
