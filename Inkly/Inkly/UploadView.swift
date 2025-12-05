import SwiftUI
import PencilKit

// 라우트 정의
private enum Route: Hashable {
    case generating(jobId: String, sourceFilename: String)
}

struct UploadView: View {
    @State private var canvas = PKCanvasView()
    @State private var isWorking = false

    @State private var jobId: String = ""
    @State private var sourceFilename: String = ""   // 업로드로 받은 원본 파일명
    @State private var errorMsg: String?

    // 네비게이션 스택 경로
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                // 캔버스
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .shadow(radius: 4, y: 2)
                    InkCanvas(
                        canvas: $canvas,
                        gridStyle: GridStyle()  // ✅ 변경: 파라미터 제거
                    )
                    .padding(8)
                }
                .frame(height: max(UIScreen.main.bounds.height * 0.78, 720))
                .frame(maxWidth: .infinity)
                .padding(.horizontal)

                // 업로드 → 생성뷰로 이동
                Button {
                    Task { await startUploadThenGoGenerating() }
                } label: {
                    Text("Upload & Generate")
                        .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .disabled(isWorking)

                if let msg = errorMsg {
                    Text(msg)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("Inkly")
            .overlay { if isWorking { GeneratingOverlayView() } }
            .background(Color(white: 0.97))
            // 목적지 등록
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .generating(jobId, sourceFilename):
                    GeneratingView(jobId: jobId, sourceFilename: sourceFilename)
                }
            }
        }
    }

    // 업로드 → jobId/filename 확보 → GeneratingView로 push
    private func startUploadThenGoGenerating() async {
        errorMsg = nil
        guard let data = canvas.exportPNG(with: GridStyle()) else {  // ✅ 변경: 파라미터 제거
            errorMsg = "PNG 변환에 실패했습니다."
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            // 1) 업로드
            let up = try await APIClient.shared.uploadPNG(data)
            guard up.ok, let fname = up.filename else {
                throw APIError.serverMessage(up.error ?? "업로드 응답 오류")
            }

            // 2) jobId 확보 (응답 우선, 없으면 파일명에서 추출, 그래도 없으면 타임스탬프)
            let jid = up.jobId
                ?? fname.split(separator: "_").first.map(String.init)
                ?? String(Int(Date().timeIntervalSince1970))

            self.jobId = jid
            self.sourceFilename = fname

            // 3) 라우팅
            path.append(Route.generating(jobId: jid, sourceFilename: fname))

        } catch {
            errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
