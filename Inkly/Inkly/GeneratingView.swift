// GeneratingView.swift
import SwiftUI

struct GeneratingView: View {
    let jobId: String
    let sourceFilename: String

    @State private var representativePath: String = ""
    @State private var isReady = false
    @State private var errorMsg: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Generating...").font(.title3).bold()
            ProgressView()

            if let msg = errorMsg {
                Text(msg).foregroundColor(.red).font(.footnote)
            }

            NavigationLink("", isActive: $isReady) {
                PreviewView(jobId: jobId, representativePath: representativePath)
            }
            .hidden()
        }
        .task { await startAndPollGenerate() }
        .navigationBarBackButtonHidden(true)
    }

    private func startAndPollGenerate() async {
        await MainActor.run { errorMsg = nil }

        do {
            let gen = try await APIClient.shared.generate(
                filename: sourceFilename,
                jobId: jobId
            )

            guard gen.ok, let _ = gen.jobId else {
                throw APIError.serverMessage(gen.error ?? "generate start failed")
            }

            try await pollStatus()
        } catch {
            await MainActor.run {
                self.errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func pollStatus() async throws {
        let maxSeconds = 30 * 60
        let interval: UInt64 = 30
        var elapsed = 0

        while elapsed < maxSeconds {
            try await Task.sleep(nanoseconds: interval * 1_000_000_000)
            elapsed += Int(interval)

            do {
                let st = try await APIClient.shared.status(jobId: jobId)

                guard st.ok else {
                    throw APIError.serverMessage(st.error ?? "status failed")
                }

                switch st.state {
                case "done":
                    if let rep = st.representative {
                        print("✅ STATUS done, rep =", rep)   // 🔍 로그
                        await MainActor.run {
                            self.representativePath = rep
                            self.isReady = true
                        }
                        return
                    } else {
                        throw APIError.serverMessage("대표 이미지 경로 없음")
                    }

                case "error":
                    throw APIError.serverMessage(st.error ?? "generate error")

                case "running", "none", nil:
                    continue

                default:
                    continue
                }
            } catch {
                await MainActor.run {
                    self.errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }

        throw APIError.serverMessage("생성이 너무 오래 걸립니다. 잠시 후 다시 시도해주세요.")
    }
}
