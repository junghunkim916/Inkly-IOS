import SwiftUI
import PencilKit

// ==========================
// 1) 그리드 스타일 파라미터
// ==========================
struct GridStyle {
    var inset: CGFloat = 20        // 전체 여백
    var rowSpacing: CGFloat = 15   // 두 직사각형 사이 간격
    
    var minorWidth: CGFloat = 4.0
    var majorWidth: CGFloat = 4.0
    var minorColor: UIColor = UIColor.gray.withAlphaComponent(0.75)
    var majorColor: UIColor = UIColor.gray.withAlphaComponent(0.75)
    
    // 첫 번째 행: 8칸, 두 번째 행: 6칸
    var firstRowCells: Int = 8
    var secondRowCells: Int = 6
}

// ==========================
// 2) 그리드 그리는 헬퍼
// ==========================
private extension CGContext {
    func drawGrid(in rect: CGRect, style: GridStyle) {
        let W = rect.width
        let H = rect.height
        
        // 전체 그리드가 차지할 높이 (캔버스 높이의 약 절반)
        let totalGridHeight = H * 0.3
        
        // 각 행의 높이 (두 행이 동일한 높이)
        let rowHeight = (totalGridHeight - style.rowSpacing) / 2
        
        // 시작 Y 위치 (상하 중앙 정렬)
        let startY = (H - totalGridHeight) / 2
        
        // 가로 영역
        let startX = style.inset
        let gridW = W - style.inset * 2
        
        // ========== 첫 번째 행 (8칸) ==========
        let firstRowY = startY
        drawRectangleRow(
            x: startX,
            y: firstRowY,
            width: gridW,
            height: rowHeight,
            cells: style.firstRowCells,
            style: style
        )
        
        // ========== 두 번째 행 (6칸) ==========
        let secondRowY = firstRowY + rowHeight + style.rowSpacing
        drawRectangleRow(
            x: startX,
            y: secondRowY,
            width: gridW,
            height: rowHeight,
            cells: style.secondRowCells,
            style: style
        )
    }
    
    private func drawRectangleRow(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, cells: Int, style: GridStyle) {
        let cellWidth = width / CGFloat(cells)
        
        // 외곽선 (굵게)
        setLineWidth(style.majorWidth)
        setStrokeColor(style.majorColor.cgColor)
        stroke(CGRect(x: x, y: y, width: width, height: height))
        
        // 내부 수직 구분선 (1부터 cells-1까지)
        setLineWidth(style.minorWidth)
        setStrokeColor(style.minorColor.cgColor)
        
        for i in 1..<cells {
            let lineX = x + CGFloat(i) * cellWidth
            move(to: CGPoint(x: lineX, y: y))
            addLine(to: CGPoint(x: lineX, y: y + height))
            strokePath()
        }
    }
}

// ==========================
// 3) 캔버스+그리드 컨테이너
// ==========================
final class GridCanvasContainer: UIView {
    let canvas: PKCanvasView
    private let gridLayer = CAShapeLayer()
    var gridStyle = GridStyle()

    init(canvas: PKCanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)

        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)

        gridLayer.contentsScale = UIScreen.main.scale
        gridLayer.frame = bounds
        layer.addSublayer(gridLayer)

        addSubview(canvas)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gridLayer.frame = bounds
        redrawGrid()
    }

    private func redrawGrid() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.drawGrid(in: CGRect(origin: .zero, size: size), style: gridStyle)
        }
        gridLayer.contents = img.cgImage
    }

    func updateGridStyle(_ style: GridStyle) {
        self.gridStyle = style
        redrawGrid()
    }
}

// ==========================
// 4) UIViewRepresentable
// ==========================
struct InkCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    var gridStyle = GridStyle()

    func makeUIView(context: Context) -> GridCanvasContainer {
        let container = GridCanvasContainer(canvas: canvas)
        container.updateGridStyle(gridStyle)
        return container
    }

    func updateUIView(_ uiView: GridCanvasContainer, context: Context) {
        uiView.updateGridStyle(gridStyle)
    }
}

// ==========================
// 5) PNG 내보내기 (격자 포함)
// ==========================
extension PKCanvasView {
    func exportPNG(with gridStyle: GridStyle = GridStyle(),
                   background: UIColor = .white) -> Data? {
        let scale = UIScreen.main.scale
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        let png = UIGraphicsImageRenderer(size: size, format: format).pngData { ctx in
            // 1) 배경 (흰색)
            background.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // 2) 그리드
            ctx.cgContext.drawGrid(in: CGRect(origin: .zero, size: size), style: gridStyle)
            // 3) 잉크 (투명 배경 이미지)
            let ink = drawing.image(from: bounds, scale: scale)
            ink.draw(at: .zero)
        }
        return png
    }
}
