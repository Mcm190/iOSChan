import SwiftUI
import WebKit

struct FullScreenImageView: View {
    let imageURL: URL
    @Environment(\.presentationMode) var presentationMode
    
    // State to control the Share Sheet
    @State private var showShareSheet = false
    @State private var fileToShare: URL?
    @State private var isDownloading = false
    
    // Helper to check if it is a video (WebM or MP4)
    var isVideo: Bool {
        let urlString = imageURL.absoluteString.lowercased()
        return urlString.contains(".webm") || urlString.contains(".mp4")
    }
    
    var body: some View {
        ZStack {
            // 1. Black background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // 2. Smart Switcher (Video vs Image)
            if isVideo {
                WebView(url: imageURL)
                    .edgesIgnoringSafeArea(.all)
            } else {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        // FIX: Wrap the loaded image in our Zoomable Helper
                        ZoomableScrollView {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                        .edgesIgnoringSafeArea(.all)
                        
                    case .failure:
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.white).font(.largeTitle)
                            Text("Could not load image").foregroundColor(.gray)
                        }
                    default:
                        ProgressView().foregroundColor(.white)
                    }
                }
            }
            
            // 3. Buttons (Overlay)
            VStack {
                HStack {
                    // Close Button
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.headline).foregroundColor(.white)
                            .padding(10).background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding()
                    
                    Spacer()
                    
                    // SHARE / SAVE BUTTON
                    if isDownloading {
                        ProgressView()
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .colorScheme(.dark)
                            .padding()
                    } else {
                        Button(action: downloadAndShare) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline).foregroundColor(.white)
                                .padding(10).background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding()
                    }
                }
                Spacer()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let file = fileToShare {
                ShareSheet(items: [file])
            }
        }
    }
    
    func downloadAndShare() {
        isDownloading = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                let filename = imageURL.lastPathComponent
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try data.write(to: tempURL)
                
                DispatchQueue.main.async {
                    self.fileToShare = tempURL
                    self.isDownloading = false
                    self.showShareSheet = true
                }
            } catch {
                print("Download failed: \(error)")
                DispatchQueue.main.async { isDownloading = false }
            }
        }
    }
}

// --- NEW HELPER: Zoomable Scroll View ---
// This wraps the native UIKit ScrollView to allow Pinch & Pan
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        // Set up the native ScrollView
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5.0 // Max Zoom (5x)
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear

        // Embed the SwiftUI view inside
        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostedView.backgroundColor = .clear
        scrollView.addSubview(hostedView)

        // Handle Double Tap to Reset
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // Update content if needed
        context.coordinator.hostingController.rootView = self.content
        assert(context.coordinator.hostingController.view.superview == uiView)
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(hostingController: UIHostingController(rootView: self.content))
    }

    // The Coordinator handles the events
    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>

        init(hostingController: UIHostingController<Content>) {
            self.hostingController = hostingController
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController.view
        }
        
        // Double Tap Logic
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            
            // Toggle between 1x and 2.5x
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                // Zoom in to where the user tapped
                let point = gesture.location(in: hostingController.view)
                let scrollSize = scrollView.frame.size
                let size = CGSize(width: scrollSize.width / 2.5, height: scrollSize.height / 2.5)
                let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }
    }
}
