import SwiftUI

enum RadarDataSource {
    case analyze(jobId: String, representativePath: String?)
    case preset([String: Double])    // reanalyze 직후 결과 그대로 전달
}

struct RadarView: View {
    let source: RadarDataSource
    let jobIdForPractice: String?    // ✅ 연습장으로 갈 때 쓸 jobId
    
    init(source: RadarDataSource, jobIdForPractice: String? = nil) {
            self.source = source
            self.jobIdForPractice = jobIdForPractice
        }

    @State private var metrics: [(String, Double)] = []
    @State private var errorMsg: String?
    @State private var isLoading = false
    @State private var pushPractice = false   // ✅ 네비게이션 플래그
    
    // ✨ 추가된 부분: 지표들의 평균 유사도 계산
    var averageSimilarity: Double {
        guard !metrics.isEmpty else { return 0.0 }
        let total = metrics.reduce(0.0) { $0 + $1.1 }
        return (total / Double(metrics.count)) * 100 // 0~1 값을 퍼센트로 변환
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("현재 글씨와의 유사도").font(.title3).bold()
            
            // ✨ 추가된 부분: 유사도 평균 표시
            Text("유사도 : \(averageSimilarity, specifier: "%.1f")%")
                .font(.headline)
                .foregroundColor(.blue)

            if isLoading { ProgressView().padding(.top, 40) }
            else if metrics.isEmpty { Text("데이터가 없습니다.").foregroundColor(.secondary) }
            else {
                RadarChart(labels: metrics.map{$0.0}, values: metrics.map{$0.1})
                    .frame(width: 260, height: 260)
                    .padding(Edge.Set.vertical, 8)
            }

            if let msg = errorMsg {
                Text(msg).foregroundColor(.red).font(.footnote)
            }

            // === ✅ 버튼 영역 ===
            HStack {
                Button("연습하러 가기") { pushPractice = true }
                    .buttonStyle(.borderedProminent)
                    // 필요하다면 조건 완화 or 제거:
                    .disabled( (jobIdForPractice?.isEmpty ?? true) ? false /*강제활성*/ : false )
                    // ↑ 그냥 항상 활성화하려면 .disabled(false) 로 두세요.

                Spacer()

                Button("다시 분석") {
                    Task { await load() }  // 원래 있던 분석 재호출
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            // PracticeView로 이동
            NavigationLink("", isActive: $pushPractice) {
                PracticeView(jobId: jobIdForPractice ?? "")
            }
            .hidden()
        }
        .padding()
        .task { await load() }
    }

    private func load(forceNetwork: Bool = false) async {
        let order = ["cosine similarity","L2 Distance","SSIM(구조적 정확도)","획 두께 농도","글자 외형"]

        // forceNetwork=true 이면 무조건 analyze 호출
        if forceNetwork {
            if case let .analyze(jid, rep) = source {
                await MainActor.run { isLoading = true; errorMsg = nil }
                defer { Task { await MainActor.run { isLoading = false } } }
                do {
                    let res = try await APIClient.shared.analyze(jobId: jid, filename: rep)
                    guard res.ok, let m = res.metrics else {
                        throw APIError.serverMessage(res.error ?? "analyze failed")
                    }
                    await MainActor.run { self.metrics = order.map { ($0, m[$0] ?? 0.0) } }
                } catch {
                    await MainActor.run { self.errorMsg = error.localizedDescription }
                }
                return
            }
        }

        switch source {
        case .preset(let m):
            await MainActor.run {
                self.metrics = order.map { ($0, m[$0] ?? 0.0) }
                self.isLoading = false
            }
        case .analyze(let jid, let rep):
            await MainActor.run { isLoading = true; errorMsg = nil }
            defer { Task { await MainActor.run { isLoading = false } } }
            do {
                let res = try await APIClient.shared.analyze(jobId: jid, filename: rep)
                guard res.ok, let m = res.metrics else {
                    throw APIError.serverMessage(res.error ?? "analyze failed")
                }
                await MainActor.run { self.metrics = order.map { ($0, m[$0] ?? 0.0) } }
            } catch {
                await MainActor.run { self.errorMsg = error.localizedDescription }
            }
        }
    }
}


struct RadarChart: View {
    let labels: [String]
    let values: [Double] // 0.0 ~ 1.0

    var body: some View {
        ZStack {
            ForEach(1..<5) { i in
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    .scaleEffect(CGFloat(i) / 4.0)
            }
            RadarPolygon(values: values)
                .fill(Color.blue.opacity(0.2))
            RadarPolygon(values: values)
                .stroke(Color.blue, lineWidth: 2)

            GeometryReader { geo in
                let r = min(geo.size.width, geo.size.height)/2
                ForEach(labels.indices, id: \.self) { i in
                    let angle = Double(i) / Double(labels.count) * 2 * .pi - .pi/2
                    let x = cos(angle) * (r + 16)
                    let y = sin(angle) * (r + 16)
                    Text(labels[i]).font(.caption2)
                        .position(x: geo.size.width/2 + x,
                                  y: geo.size.height/2 + y)
                }
            }
        }
        .padding(Edge.Set.vertical, 8) // ← 위 1) 수정 적용
    }
}

struct RadarPolygon: Shape {
    let values: [Double] // 0...1
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = max(values.count, 1)
        let cx = rect.midX, cy = rect.midY
        let r = min(rect.width, rect.height)/2
        for i in 0..<n {
            let v = max(0, min(1, values[i]))
            let ang = Double(i)/Double(n) * 2 * .pi - .pi/2
            let x = cx + CGFloat(cos(ang)) * CGFloat(v) * r
            let y = cy + CGFloat(sin(ang)) * CGFloat(v) * r
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        if n > 1 { p.closeSubpath() }
        return p
    }
}
