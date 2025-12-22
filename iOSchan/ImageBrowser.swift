import SwiftUI
import Photos
import UIKit

struct ImageBrowser: View {
    let media: [MediaItem]
    @State var currentIndex: Int
    @Binding var isPresented: Bool
    let onBack: (() -> Void)?

    @State private var showSaveAlert = false
    @State private var saveMessage: String = ""

    init(media: [MediaItem], currentIndex: Int, isPresented: Binding<Bool>, onBack: (() -> Void)? = nil) {
        self.media = media
        _currentIndex = State(initialValue: currentIndex)
        _isPresented = isPresented
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(media.indices, id: \ .self) { idx in
                    let item = media[idx]
                    Group {
                        if item.isVideo || item.isGif {
                            WebView(url: item.fullURL)
                                .edgesIgnoringSafeArea(.all)
                        } else {
                            AsyncImage(url: item.fullURL) { phase in
                                switch phase {
                                case .success(let image):
                                    ZoomableScrollView {
                                        image.resizable().aspectRatio(contentMode: .fit)
                                    }
                                case .failure:
                                    Image(systemName: "exclamationmark.triangle").foregroundColor(.white)
                                default:
                                    ProgressView().foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .tag(idx)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))

            VStack {
                HStack(spacing: 12) {
                    // Back to gallery (if provided)
                    if let onBack = onBack {
                        Button(action: {
                            isPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onBack()
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.headline).foregroundColor(.white)
                                .padding(10).background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }

                    // Close
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.headline).foregroundColor(.white)
                            .padding(10).background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }

                    Spacer()

                    // Save button
                    Button(action: { saveCurrentMedia() }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.headline).foregroundColor(.white)
                            .padding(10).background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }
                .padding()
                Spacer()
            }
        }
        .alert(saveMessage, isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) { }
        }
    }

    private func saveCurrentMedia() {
        guard media.indices.contains(currentIndex) else { return }
        let item = media[currentIndex]

        // Treat GIFs like video/animated media and save them to Files
        if item.isVideo || item.isGif {
            saveVideo(url: item.fullURL)
        } else {
            saveImage(url: item.fullURL)
        }
    }

    private func saveImage(url: URL) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let uiImage = UIImage(data: data) else {
                    saveMessage = "Failed to decode image"
                    showSaveAlert = true
                    return
                }

                UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                saveMessage = "Image saved to Photos"
                showSaveAlert = true
            } catch {
                saveMessage = "Failed to download image: \(error.localizedDescription)"
                showSaveAlert = true
            }
        }
    }

    private func saveVideo(url: URL) {
        Task {
            do {
                let (fileURL, _) = try await downloadToTemporaryFile(from: url)

                // Create a dated folder in Documents similar to ThreadDetailView's format.
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "ddMMyyyy"
                let dateString = dateFormatter.string(from: Date())

                let pathComponents = url.pathComponents
                var board = "UNKNOWN"
                if pathComponents.count >= 3 {
                    board = pathComponents[1].uppercased()
                }
                let tim = url.deletingPathExtension().lastPathComponent
                let folderName = "(\(board)-\(tim)-\(dateString))"

                let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let destinationFolder = documentsUrl.appendingPathComponent(folderName, isDirectory: true)
                if !FileManager.default.fileExists(atPath: destinationFolder.path) {
                    try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                }

                let destinationFile = destinationFolder.appendingPathComponent(url.lastPathComponent)
                var finalDestination = destinationFile
                if FileManager.default.fileExists(atPath: destinationFile.path) {
                    finalDestination = destinationFolder.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                }

                try FileManager.default.moveItem(at: fileURL, to: finalDestination)

                await MainActor.run {
                    saveMessage = "Saved to Files."
                    showSaveAlert = true
                }
            } catch {
                await MainActor.run {
                    saveMessage = "Failed to save video: \(error.localizedDescription)"
                    showSaveAlert = true
                }
            }
        }
    }

    private func downloadToTemporaryFile(from url: URL) async throws -> (URL, URLResponse) {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return (dest, response)
    }
}
