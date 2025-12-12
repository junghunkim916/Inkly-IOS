import SwiftUI

enum RadarDataSource {
    case analyze(jobId: String)
    case overlay(base: [String: Double], rewrite: [String: Double])
}

struct RadarView: View {
    let source: RadarDataSource
    let jobIdForPractice: String?

    @State private var baseMetrics: [String: Double] = [:]
    @State private var rewriteMetrics: [String: Double] = [:]
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var pushPractice = false

//    private let order = ["AI 필체 유사도","특징 일치도","구조적 정확도","획 농도","글자 외형"]
    private var activeMetrics: [String: Double] {
        rewriteMetrics.isEmpty ? baseMetrics : rewriteMetrics
    }

    private var labels: [String] {
        metricOrder
    }

    private var values: [Double] {
        metricOrder.map { activeMetrics[$0] ?? 0 }
    }
    
    private let metricOrder = [
        "AI 필체 유사도",
        "특징 일치도",
        "구조적 정확도",
        "획 농도",
        "글자 외형"
    ]

    private var avgSimilarity: Double {
        let values = rewriteMetrics.isEmpty ? baseMetrics.values : rewriteMetrics.values
        guard !values.isEmpty else { return 0 }
        return values.reduce(0,+) / Double(values.count) * 100
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("현재 글씨와의 유사도")
                .font(.title3).bold()

            Text("유사도 : \(avgSimilarity, specifier: "%.1f")%")
                .font(.headline)
                .foregroundColor(rewriteMetrics.isEmpty ? .blue : .yellow)

            if isLoading {
                ProgressView()
            } else {
                ZStack {
                    if !baseMetrics.isEmpty {
                        RadarChart(
                            labels: metricOrder,
                            values: metricOrder.map { baseMetrics[$0] ?? 0 },
                            color: .blue
                        )
                    }

                    if !rewriteMetrics.isEmpty {
                        RadarChart(
                            labels: metricOrder,
                            values: metricOrder.map { rewriteMetrics[$0] ?? 0 },
                            color: .yellow
                        )
                    }
                }
                .frame(width: 260, height: 260)
            }

            if let msg = errorMsg {
                Text(msg).foregroundColor(.red)
            }

            HStack {
                Button("연습하러 가기") {
                    pushPractice = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(jobIdForPractice == nil)

                Spacer()

                Button("다시 분석") {
                    Task { await load(force: true) }
                }
                .buttonStyle(.bordered)
            }

            NavigationLink("", isActive: $pushPractice) {
                PracticeView(
                    jobId: jobIdForPractice ?? "",
                    baseMetrics: baseMetrics
                )
            }
            .hidden()
        }
        .padding()
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        switch source {

        case .overlay(let base, let rewrite):
            self.baseMetrics = base
            self.rewriteMetrics = rewrite

        case .analyze(let jobId):
            isLoading = true
            defer { isLoading = false }

            do {
                if force {
                    // 🔥🔥🔥 핵심: reanalyze 결과를 써야 한다
                    guard
                        let practicePNG = PracticeStore.shared.latestPNG
                    else {
                        errorMsg = "연습 데이터가 없습니다."
                        return
                    }

                    let res = try await APIClient.shared.reanalyze(
                        practicePNG: practicePNG,
                        jobId: jobId
                    )

                    self.rewriteMetrics = res.metrics ?? [:]

                } else {
                    // 🔵 최초 분석
                    let res = try await APIClient.shared.analyze(jobId: jobId, filename: nil)
                    self.baseMetrics = res.metrics ?? [:]
                    self.rewriteMetrics = [:]
                }

            } catch {
                errorMsg = error.localizedDescription
            }
        }
    }
}

// MARK: - Radar Components

struct RadarChart: View {
    let labels: [String]
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 배경 원
                ForEach(1..<5) { i in
                    Circle()
                        .stroke(Color.gray.opacity(0.2))
                        .scaleEffect(CGFloat(i)/4)
                }

                // 레이더 도형
                RadarPolygon(values: values)
                    .fill(color.opacity(0.25))

                RadarPolygon(values: values)
                    .stroke(color, lineWidth: 2)

                // 🔥🔥🔥 축 라벨
                ForEach(labels.indices, id: \.self) { i in
                    let angle = Double(i) / Double(labels.count) * 2 * .pi - .pi/2
                    let r = min(geo.size.width, geo.size.height) / 2

                    Text(labels[i])
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .position(
                            x: geo.size.width / 2 + CGFloat(cos(angle)) * r * 0.9,
                            y: geo.size.height / 2 + CGFloat(sin(angle)) * r * 0.9
                        )
                }
            }
        }
    }
}

struct RadarPolygon: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = values.count
        let r = min(rect.width, rect.height)/2
        let c = CGPoint(x: rect.midX, y: rect.midY)

        for i in 0..<n {
            let v = max(0, min(1, values[i]))
            let a = Double(i)/Double(n) * 2 * .pi - .pi/2
            let x = c.x + CGFloat(cos(a)) * CGFloat(v) * r
            let y = c.y + CGFloat(sin(a)) * CGFloat(v) * r
            i == 0 ? p.move(to: .init(x: x, y: y)) : p.addLine(to: .init(x: x, y: y))
        }
        p.closeSubpath()
        return p
    }
}
