import SwiftUI
import PencilKit
import UIKit
import CoreImage // 이미지 필터링을 위해 추가

struct PracticeView: View {
    let jobId: String
    let representativePath: String // 서버에 있는 원본 이미지 경로

    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    @State private var bgImage: UIImage?
    @State private var isLoadingBG = false
    @State private var err: String?
    @State private var isWorking = false

    // 재분석 결과 저장 및 이동 트리거
    @State private var lastMetrics: [String: Double] = [:]
    @State private var pushRadarAgain = false

    var body: some View {
        VStack(spacing: 16) {
            Text("연습장")
                .font(.title3).bold()

            ZStack {
                // 1. [배경] 회색으로 변환된 가이드 이미지
                if let img = bgImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 2)
                } else {
                    // 로딩 Placeholder
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.1))
                        .overlay(
                            VStack(spacing: 8) {
                                if isLoadingBG { ProgressView() }
                                Text(isLoadingBG ? "이미지 변환 중..." : "이미지 없음")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        )
                }

                // 2. [전경] 투명 캔버스 (사용자 필기 영역)
                PracticeCanvas(canvas: $canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .frame(height: 320)
            .padding(.horizontal)

            // 툴바
            HStack {
                Button("지우개") { canvas.tool = PKEraserTool(.vector) }
                Button("펜") { canvas.tool = PKInkingTool(.pen, color: .black, width: 4) }
                Button("지우기") { canvas.drawing = PKDrawing() }
                Spacer()
            }
            .padding(.horizontal)

            // 하단 버튼
            HStack {
                Button {
                    Task { await exportInkAndReanalyze() }
                } label: {
                    if isWorking { ProgressView().padding(.horizontal, 5) }
                    else { Text("재검사") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || bgImage == nil)

                Spacer()

                Button("닫기") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            if let e = err {
                Text(e).font(.footnote).foregroundColor(.red)
            }

            // 재검사 완료 시 결과 화면으로 이동
            NavigationLink("", isActive: $pushRadarAgain) {
                RadarView(source: .preset(lastMetrics))
            }
            .hidden()
        }
        .padding()
        .task { await loadAndConvertBackground() }
    }

    // MARK: - 로직 1: 원본 다운로드 -> 내부 함수로 회색 변환
    private func loadAndConvertBackground() async {
        isLoadingBG = true; err = nil
        defer { isLoadingBG = false }

        do {
            // 1. 서버에서 원본(검은색) 다운로드
            let data = try await APIClient.shared.download(path: representativePath)
            guard let original = UIImage(data: data) else {
                err = "이미지 데이터 손상"
                return
            }

            // 2. 뷰 내부 함수를 통해 회색으로 변환
            guard let faded = applyGrayFilter(to: original) else {
                err = "필터 적용 실패"
                return
            }

            // 3. UI 적용
            await MainActor.run {
                self.bgImage = faded
            }
        } catch {
            err = error.localizedDescription
        }
    }

    // MARK: - 로직 2: 재검사 (잉크 추출 -> 업로드)
    private func exportInkAndReanalyze() async {
        err = nil
        // 배경 제외하고 쓴 글씨만 추출
        guard let png = exportInkPNG() else {
            err = "필기 내용이 없습니다."
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let res = try await APIClient.shared.reanalyze(practicePNG: png)
            guard res.ok, let m = res.metrics else {
                throw APIError.serverMessage(res.error ?? "재분석 실패")
            }

            await MainActor.run {
                self.lastMetrics = m
                self.pushRadarAgain = true
            }
        } catch {
            err = error.localizedDescription
        }
    }

    // MARK: - 헬퍼 1: 잉크만 PNG로 추출
    private func exportInkPNG() -> Data? {
        let scale = UIScreen.main.scale
        let bounds = canvas.bounds
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // drawing.image는 배경 뷰(bgImage)를 포함하지 않고 스트로크만 렌더링함
        let inkImage = canvas.drawing.image(from: bounds, scale: scale)
        return inkImage.pngData()
    }

    // MARK: - 헬퍼 2: 검은색 -> 회색 변환 필터 (통합됨)
    private func applyGrayFilter(to image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) ?? CIImage(image: image, options: nil) else {
            return nil
        }
        
        // 밝기 조절 필터 생성
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        // 밝기(Brightness): 0.0(검정) -> 0.6(회색). (흰색 배경은 1.0 유지)
        filter.setValue(0.6, forKey: kCIInputBrightnessKey)
        filter.setValue(0.0, forKey: kCIInputContrastKey)
        
        guard let output = filter.outputImage else { return nil }
        
        // 렌더링
        let context = CIContext()
        if let cg = context.createCGImage(output, from: output.extent) {
            return UIImage(cgImage: cg)
        }
        return nil
    }
}