import SwiftUI
import PencilKit
import UIKit

struct PracticeView: View {
    let jobId: String

    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    @State private var bgImage: UIImage?
    @State private var isLoadingBG = false
    @State private var err: String?
    @State private var isWorking = false

    // reanalyze 결과 임시 저장 → RadarView로 preset 전달
    @State private var lastMetrics: [String: Double] = [:]
    @State private var pushRadarAgain = false

    var body: some View {
        VStack(spacing: 16) {
            Text("연습장").font(.title3).bold()

            ZStack {
                if let img = bgImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 2)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .overlay(
                            VStack(spacing: 8) {
                                if isLoadingBG { ProgressView("배경 불러오는 중…") }
                                else { Text("배경 없음").foregroundColor(.gray) }
                            }
                        )
                }

                PracticeCanvas(canvas: $canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .frame(height: 320)
            .padding(.horizontal)

            HStack {
                Button("지우개") { canvas.tool = PKEraserTool(.vector) }
                Button("펜") { canvas.tool = PKInkingTool(.pen, color: .black, width: 4) }
                Button("모두 지우기") { canvas.drawing = PKDrawing() }
                Spacer()
            }
            .padding(.horizontal)

            HStack {
                Button("재검사") { Task { await exportInkAndReanalyze() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)

                Spacer()

                Button("종료하기") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            if let e = err { Text(e).font(.footnote).foregroundColor(.red) }

            // ✅ 방금 받은 지표 그대로 넘겨서 즉시 레이더 그리기
            NavigationLink("", isActive: $pushRadarAgain) {
                RadarView(source: .preset(lastMetrics))
            }
            .hidden()
        }
        .padding()
        .task { await loadPracticeBackground() }
    }

    private func loadPracticeBackground() async {
        isLoadingBG = true; err = nil
        defer { isLoadingBG = false }
        do {
            let data = try await APIClient.shared.practice()
            guard let img = UIImage(data: data) else { err = "배경 이미지 디코딩 실패"; return }
            bgImage = img
        } catch {
            err = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // ✅ 핵심 수정: throw 밖에서 결과를 저장하고 push
    private func exportInkAndReanalyze() async {
        err = nil
        guard let png = exportInkPNG() else { err = "잉크 추출 실패"; return }
        isWorking = true
        defer { isWorking = false }

        do {
            let res = try await APIClient.shared.reanalyze(practicePNG: png)
            guard res.ok else {
                throw APIError.serverMessage(res.error ?? "reanalyze failed")
            }
            let m = res.metrics ?? [:]          // ✅ 실제 값
            await MainActor.run {
                self.lastMetrics = m            // ✅ 값 저장
                self.pushRadarAgain = true      // ✅ 즉시 이동
            }
        } catch {
            err = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func exportInkPNG() -> Data? {
        let scale = UIScreen.main.scale
        let bounds = canvas.bounds
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        let inkOnly = canvas.drawing.image(from: bounds, scale: scale)
        return inkOnly.pngData()
    }
}
