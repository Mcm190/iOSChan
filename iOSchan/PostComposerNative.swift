import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// Simple storage to hold the captcha ID if 4chan provides one
final class CaptchaStorage {
    static let shared = CaptchaStorage()
    private init() {}
    var captchaId: String? = nil
}

struct PostComposerNative: View {
    let boardID: String
    let threadNo: Int? // nil -> new thread

    init(boardID: String, threadNo: Int?, initialComment: String? = nil) {
        self.boardID = boardID
        self.threadNo = threadNo
        _comment = State(initialValue: initialComment ?? "")
    }

    @Environment(\.dismiss) private var dismiss

    // Form Fields
    @State private var name: String = ""
    @State private var subject: String = ""
    @State private var email: String = ""
    @State private var comment: String = ""

    // Attachment
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedData: Data? = nil
    @State private var selectedFilename: String? = nil

    // Captcha State
    @State private var captchaToken: String? = nil
    @State private var showingCaptcha = false
    
    // Submission State
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false
    @State private var showSafari = false

    private var postURL: URL {
        if let threadNo {
            return URL(string: "https://boards.4chan.org/\(boardID)/thread/\(threadNo)")!
        } else {
            return URL(string: "https://boards.4chan.org/\(boardID)/")!
        }
    }

    var body: some View {
        NavigationView {
            Form {
                // Header Information
                Section(header: Text("Posting to /\(boardID)/")) {
                    if let threadNo {
                        Text("Replying to No. \(threadNo)")
                            .foregroundColor(.secondary)
                    } else {
                        Text("Creating a New Thread")
                            .foregroundColor(.secondary)
                    }
                }

                // Identity
                Section(header: Text("Identity (optional)")) {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }

                // Subject (Only show for new threads)
                if threadNo == nil {
                    Section(header: Text("Subject (optional)")) {
                        TextField("Subject", text: $subject)
                            .autocorrectionDisabled()
                    }
                }

                // Comment Body
                Section(header: Text("Comment")) {
                    TextEditor(text: $comment)
                        .frame(minHeight: 180)
                }

                // Media Attachment
                Section(header: Text("Attachment")) {
                    PhotosPicker(selection: $selectedItem, matching: .any(of: [.images, .videos])) {
                        HStack {
                            Image(systemName: "paperclip")
                            Text(selectedFilename ?? "Choose Image/Video")
                        }
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task { await loadSelectedItem(newItem) }
                    }
                    
                    if let _ = selectedData {
                        Button("Remove Attachment", role: .destructive) {
                            selectedItem = nil
                            selectedData = nil
                            selectedFilename = nil
                        }
                    }
                }

                // Captcha Section
                Section(header: Text("CAPTCHA"), footer: captchaStatusFooter) {
                    Button(action: {
                        // Reset error and open the captcha sheet immediately
                        // The ChanCaptchaView handles the loading logic now.
                        errorMessage = nil
                        showingCaptcha = true
                    }) {
                        if captchaToken == nil {
                            Text("Solve hCaptcha")
                        } else {
                            Text("Re-solve hCaptcha")
                        }
                    }
                }

                // Submit Button
                Section {
                    Button(action: submit) {
                        if isSubmitting {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 5)
                                Text("Posting...")
                            }
                        } else {
                            Label("Post", systemImage: "paperplane.fill")
                        }
                    }
                    .disabled(isSubmitting || isFormInvalid)
                }
            }
            .navigationTitle(threadNo == nil ? "New Thread" : "Reply")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(action: { showSafari = true }) {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open in Safari")
                }
            }
            // CAPTCHA SHEET
            .sheet(isPresented: $showingCaptcha) {
                // We add the 'onToken:' label explicitly to fix the "Ambiguous init" error
                ChanCaptchaView(
                    boardID: boardID,
                    threadNo: threadNo,
                    onToken: { token, cid in
                        self.captchaToken = token
                        if let cid = cid {
                            CaptchaStorage.shared.captchaId = cid
                        }
                        self.showingCaptcha = false
                    }
                )
            }
            .sheet(isPresented: $showSafari) {
                SafariView(url: postURL)
            }
            // Error Alert
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    // MARK: - Computed Properties

    private var isFormInvalid: Bool {
        let hasText = !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = selectedData != nil
        
        // 4chan rules: You usually need either text OR an image (unless replying, where text is required if no image)
        // But strictly, you need a Captcha token.
        let hasContent = hasText || hasImage
        return !hasContent || captchaToken == nil
    }

    private var captchaStatusFooter: some View {
        Text(captchaToken == nil ? "Required before posting." : "Token acquired ✓")
            .foregroundColor(captchaToken == nil ? .red : .green)
    }

    // MARK: - Actions

    private func loadSelectedItem(_ item: PhotosPickerItem?) async {
        guard let item else {
            selectedData = nil
            selectedFilename = nil
            return
        }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    self.selectedData = data
                    // Determine extension based on content type
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "bin"
                    
                    // Simple logic to name files. 4chan renames them anyway,
                    // but the extension is critical for the server to accept it.
                    self.selectedFilename = "upload.\(ext)"
                }
            }
        } catch {
            await MainActor.run {
                print("Failed to load attachment: \(error)")
                self.selectedData = nil
                self.selectedFilename = nil
            }
        }
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let payload = PostPayload(
                    boardID: boardID,
                    threadNo: threadNo,
                    name: name.isEmpty ? nil : name,
                    subject: subject.isEmpty ? nil : subject,
                    email: email.isEmpty ? nil : email,
                    comment: comment,
                    imageData: selectedData,
                    imageFilename: selectedFilename,
                    captchaToken: captchaToken,
                    captchaId: CaptchaStorage.shared.captchaId
                )

                try await PostingManager.shared.submit(payload)

                await MainActor.run {
                    // Clear the global captcha ID after successful use
                    CaptchaStorage.shared.captchaId = nil
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.showErrorAlert = true
                    self.isSubmitting = false
                }
            }
        }
    }
}
