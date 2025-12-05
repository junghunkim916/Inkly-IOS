// PreviewView.swift
import SwiftUI
import UIKit

struct PreviewView: View {
    let jobId: String
    let representativePath: String

    @State private var imageData: Data?
    @State private var uiImage: UIImage?
    @State private var showingShare = false
    @State private var errorMsg: String?
    @State private var pushRadar = false
    @State private var isLoading = false

    var body: some View {
        print("📦 PreviewView received repPath =", representativePath)

        let screenHeight = UIScreen.main.bounds.height

        return ScrollView {
            VStack(spacing: 16) {
                Text("미리보기 / 다운로드")
                    .font(.title3)
                    .bold()

                Group {
                    if let image = uiImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: screenHeight * 0.3)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.08))
                            .frame(height: 260)
                            .overlay(
                                VStack(spacing: 8) {
                                    if isLoading { ProgressView() }
                                    Text(isLoading ? "이미지를 불러오는 중..." : "이미지가 없습니다.")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                            )
                    }
                }
                .padding(.horizontal)

                HStack {
                    Button("Download") { showingShare = true }
                        .buttonStyle(.bordered)
                        .disabled(imageData == nil)

                    Spacer()

                    Button("손글씨 분석하기") { pushRadar = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(uiImage == nil)
                }
                .padding(.horizontal)

                if let msg = errorMsg {
                    Text(msg)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical)
        }
        .task(id: representativePath) {
            // repPath가 바뀔 때마다 다시 호출
            await loadRepresentative(filename: representativePath)
        }
        .sheet(isPresented: $showingShare) {
            if let data = imageData {
                ShareSheet(activityItems: [dataToTempURL(data: data, name: "inkly_result.png") as Any])
            } else {
                Text("아직 다운로드된 이미지가 없습니다.").padding()
            }
        }
        .background(
            NavigationLink("", isActive: $pushRadar) {
                RadarView(
                    source: .analyze(jobId: jobId, representativePath: representativePath),
                    jobIdForPractice: jobId
                )
            }
            .hidden()
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    private func loadRepresentative(filename: String) async {
        await MainActor.run {
            // 처음엔 에러 지우고 로딩만 켜두자
            errorMsg = nil
            isLoading = true
        }
        defer { Task { await MainActor.run { isLoading = false } } }

        do {
            let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
                                  .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            print("🔎 loadRepresentative trimmed =", trimmed)

            // 👉 아직 값이 안 온 상태라면 조용히 리턴 (에러 메시지 X)
            if trimmed.isEmpty {
                return
            }

            let d = try await APIClient.shared.download(path: trimmed)
            guard let img = UIImage(data: d) else {
                await MainActor.run {
                    self.errorMsg = "이미지 디코딩 실패(손상 데이터?)"
                    self.imageData = nil
                    self.uiImage = nil
                }
                return
            }

            await MainActor.run {
                self.imageData = d
                self.uiImage   = img
            }
        } catch {
            await MainActor.run {
                self.errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.imageData = nil
                self.uiImage = nil
            }
        }
    }

    private func dataToTempURL(data: Data, name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }
    
}
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
