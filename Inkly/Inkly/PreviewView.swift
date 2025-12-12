// PreviewView.swift
import SwiftUI
import UIKit

struct PreviewView: View {
    let jobId: String
    let representativePath: String

    // MARK: - Config
    private let charCount = 14

    /// 서버 폴더/파일 네이밍이 다르면 여기만 수정하면 됨.
    /// (예시) original:  <jobId>/handwriting/0.png ... 13.png
    ///       generated: <jobId>/Generation/0.png ... 13.png
    private func originalCharPath(_ i: Int) -> String {
        "result\(jobId)/handwriting/\(i).png"
    }

    private func generatedCharPath(_ i: Int) -> String {
        "result\(jobId)/generation/\(i).png"
    }

    // MARK: - State
    @State private var representativeData: Data?
    @State private var representativeImage: UIImage?

    @State private var originalCharImages: [UIImage?] = Array(repeating: nil, count: 14)
    @State private var generatedCharImages: [UIImage?] = Array(repeating: nil, count: 14)

    @State private var selectedIndex: Int? = nil

    @State private var showingShare = false
    @State private var showingZoom = false

    @State private var errorMsg: String?
    @State private var pushRadar = false
    @State private var isLoadingRepresentative = false
    @State private var isLoadingChars = false

    var body: some View {
        print("📦 PreviewView received repPath =", representativePath)

        let screenHeight = UIScreen.main.bounds.height

        return ScrollView {
            VStack(spacing: 16) {
                Text("미리보기 / 다운로드")
                    .font(.title3)
                    .bold()

                // (선택) 대표 이미지: 서버가 준 대표 결과(붙인 1장)가 있으면 보여줌
                Group {
                    if let image = representativeImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: screenHeight * 0.25)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 2)
                            .onTapGesture { showingZoom = true }
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.08))
                            .frame(height: 180)
                            .overlay(
                                VStack(spacing: 8) {
                                    if isLoadingRepresentative { ProgressView() }
                                    Text(isLoadingRepresentative ? "대표 이미지를 불러오는 중..." : "대표 이미지가 없습니다.")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                }
                            )
                    }
                }
                .padding(.horizontal)

                // ✅ 14글자 비교 뷰
                VStack(alignment: .leading, spacing: 18) {
                    CharRowView(
                        title: "내가 쓴 글씨 (14)",
                        images: originalCharImages,
                        selectedIndex: $selectedIndex,
                        onTap: { idx in
                            selectedIndex = idx
                            showingZoom = true
                        }
                    )

                    Divider().padding(.horizontal, 4)

                    CharRowView(
                        title: "개선된 글씨 (14)",
                        images: generatedCharImages,
                        selectedIndex: $selectedIndex,
                        onTap: { idx in
                            selectedIndex = idx
                            showingZoom = true
                        }
                    )

                    if isLoadingChars {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("글자 이미지를 불러오는 중...")
                                .foregroundColor(.secondary)
                                .font(.footnote)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)

                HStack {
                    Button("Download") { showingShare = true }
                        .buttonStyle(.bordered)
                        .disabled(representativeData == nil)

                    Spacer()

                    Button("손글씨 분석하기") { pushRadar = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(representativeImage == nil)
                }
                .padding(.horizontal)

                if let msg = errorMsg {
                    Text(msg)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .padding(.top, 4)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .task(id: representativePath) {
            // repPath가 바뀔 때마다 다시 호출
            await loadRepresentative(filename: representativePath)
            await loadCharSets()
        }
        .sheet(isPresented: $showingShare) {
            if let data = representativeData {
                ShareSheet(activityItems: [dataToTempURL(data: data, name: "inkly_result.png") as Any])
            } else {
                Text("아직 다운로드된 이미지가 없습니다.").padding()
            }
        }
        .sheet(isPresented: $showingZoom) {
            ZoomCompareSheet(
                representative: representativeImage,
                original: selectedIndex.flatMap { safeImage(originalCharImages, $0) },
                generated: selectedIndex.flatMap { safeImage(generatedCharImages, $0) },
                index: selectedIndex
            )
        }
        .background(
            NavigationLink("", isActive: $pushRadar) {
                RadarView(
                    source: .analyze(jobId: jobId),
                    jobIdForPractice: jobId
                )
            }
            .hidden()
        )
        .navigationBarTitleDisplayMode(.inline)
    }
    private func loadRepresentative(filename: String) async {
        await MainActor.run {
            errorMsg = nil
            isLoadingRepresentative = true
        }
        defer { Task { await MainActor.run { isLoadingRepresentative = false } } }

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
                    self.representativeData = nil
                    self.representativeImage = nil
                }
                return
            }

            await MainActor.run {
                self.representativeData = d
                self.representativeImage = img
            }
        } catch {
            await MainActor.run {
                self.errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.representativeData = nil
                self.representativeImage = nil
            }
        }
    }

    private func safeImage(_ arr: [UIImage?], _ i: Int) -> UIImage? {
        guard i >= 0, i < arr.count else { return nil }
        return arr[i]
    }

    private func decodeImage(_ data: Data) -> UIImage? {
        UIImage(data: data)
    }

    private func downloadImageOrNil(path: String) async -> UIImage? {
        do {
            let d = try await APIClient.shared.download(path: path)
            return decodeImage(d)
        } catch {
            return nil
        }
    }

    private func loadCharSets() async {
        await MainActor.run {
            isLoadingChars = true
            // 로딩 시 기존 이미지 유지하고, 선택 인덱스는 유지
        }
        defer { Task { await MainActor.run { isLoadingChars = false } } }

        // charCount와 State 배열 길이가 다르면 맞춰줌
        await MainActor.run {
            if originalCharImages.count != charCount {
                originalCharImages = Array(repeating: nil, count: charCount)
            }
            if generatedCharImages.count != charCount {
                generatedCharImages = Array(repeating: nil, count: charCount)
            }
        }

        // TaskGroup으로 병렬 다운로드
        await withTaskGroup(of: (Bool, Int, UIImage?).self) { group in
            for i in 0..<charCount {
                let op = originalCharPath(i)
                let gp = generatedCharPath(i)

                group.addTask { (true, i, await downloadImageOrNil(path: op)) }
                group.addTask { (false, i, await downloadImageOrNil(path: gp)) }
            }

            for await (isOriginal, idx, image) in group {
                await MainActor.run {
                    if isOriginal {
                        if idx < originalCharImages.count { originalCharImages[idx] = image }
                    } else {
                        if idx < generatedCharImages.count { generatedCharImages[idx] = image }
                    }
                }
            }
        }

        // 선택 인덱스가 비어 있으면 첫 번째로 기본 선택
        await MainActor.run {
            if selectedIndex == nil {
                selectedIndex = 0
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

// MARK: - Reusable Character Row
struct CharRowView: View {
    let title: String
    let images: [UIImage?]
    @Binding var selectedIndex: Int?
    let onTap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                // 고급 UX: 선택 인덱스 표시
                if let idx = selectedIndex {
                    Text("선택: \(idx + 1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(images.indices, id: \.self) { i in
                        CharCell(
                            image: images[i],
                            index: i,
                            isSelected: selectedIndex == i
                        )
                        .onTapGesture {
                            selectedIndex = i
                            onTap(i)
                        }
                        .accessibilityLabel("char_\(i)")
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }
}

struct CharCell: View {
    let image: UIImage?
    let index: Int
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.08))
                        .overlay(
                            Text("–")
                                .foregroundColor(.secondary)
                        )
                }
            }
            .frame(width: 64, height: 64)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(radius: isSelected ? 2 : 0)

            // 인덱스 배지
            Text("\(index + 1)")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .padding(6)
        }
    }
}

// MARK: - Zoom Sheet (Advanced UX)
struct ZoomCompareSheet: View {
    let representative: UIImage?
    let original: UIImage?
    let generated: UIImage?
    let index: Int?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let idx = index {
                        Text("선택한 글자: \(idx + 1)번째")
                            .font(.headline)
                            .padding(.horizontal)
                    }

                    if let rep = representative {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("대표 이미지")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            Image(uiImage: rep)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("원본")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            ZoomImageBox(image: original)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("개선")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            ZoomImageBox(image: generated)
                        }
                    }
                    .padding(.horizontal)

                    Text("팁: 위/아래 행에서 같은 번호를 누르면 두 결과가 동시에 비교됩니다.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                .padding(.top, 12)
            }
            .navigationTitle("확대 보기")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ZoomImageBox: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.08))
                    .frame(height: 220)
                    .overlay(
                        Text("이미지 없음")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    )
            }
        }
    }
}
