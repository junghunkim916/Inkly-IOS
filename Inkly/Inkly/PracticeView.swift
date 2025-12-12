import SwiftUI
import PencilKit

struct PracticeView: View {
    let jobId: String
    let baseMetrics: [String: Double]

    @Environment(\.dismiss) private var dismiss

    @State private var canvas = PKCanvasView()
    @State private var bgImage: UIImage?
    @State private var rewriteMetrics: [String: Double] = [:]
    @State private var pushRadar = false
    @State private var isWorking = false
    @State private var errorMsg: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("연습장")
                .font(.title3).bold()

            // ✅ UploadView와 동일한 카드 크기
            ZStack {
                if let img = bgImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 450, height: 900)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                PracticeCanvasSized(
                    canvas: $canvas,
                    size: CGSize(width: 500, height: 1000)
                )
            }

            HStack {
                Button("재검사") {
                    Task { await reanalyze() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)

                Spacer()

                Button("닫기") { dismiss() }
            }

            if let err = errorMsg {
                Text(err).foregroundColor(.red)
            }

            NavigationLink("", isActive: $pushRadar) {
                RadarView(
                    source: .overlay(
                        base: baseMetrics,
                        rewrite: rewriteMetrics
                    ),
                    jobIdForPractice: jobId
                )
            }
            .hidden()
        }
        .padding()
        .task { await loadBackground() }
    }

    private func loadBackground() async {
        do {
            let data = try await APIClient.shared.practice(jobId: jobId)
            bgImage = UIImage(data: data)
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func reanalyze() async {
        guard let png = canvas.drawing
            .image(from: canvas.bounds, scale: UIScreen.main.scale)
            .pngData()
        else {
            errorMsg = "연습 데이터를 PNG로 변환할 수 없습니다."
            return
        }

        // 🔥🔥🔥 이 줄이 핵심
        PracticeStore.shared.latestPNG = png

        isWorking = true
        defer { isWorking = false }

        do {
            let res = try await APIClient.shared.reanalyze(
                practicePNG: png,
                jobId: jobId
            )

            rewriteMetrics = res.metrics ?? [:]
            pushRadar = true

        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

struct PracticeCanvasSized: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    let size: CGSize

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.backgroundColor = .clear
        canvas.frame = CGRect(origin: .zero, size: size)
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.frame = CGRect(origin: .zero, size: size)
    }
}

