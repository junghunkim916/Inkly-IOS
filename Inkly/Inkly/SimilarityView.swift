import SwiftUI

struct SimilarityView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("현재 글씨와의 유사도")
                .font(.title2).bold()

            // 레이더차트 Placeholder
            ZStack {
                ForEach([1, 2, 3], id: \.self) { i in
                    Polygon(sides: 6)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        .frame(width: CGFloat(220 - (i-1)*50), height: CGFloat(220 - (i-1)*50))
                }
            }.frame(height: 260)

            Spacer()
        }
        .padding()
        .navigationTitle("Similarity")
    }
}

struct Polygon: Shape {
    var sides: Int
    func path(in rect: CGRect) -> Path {
        guard sides > 2 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var path = Path()
        for i in 0..<sides {
            let a = (CGFloat(i) / CGFloat(sides)) * .pi * 2 - .pi/2
            let p = CGPoint(x: center.x + cos(a)*r, y: center.y + sin(a)*r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}
