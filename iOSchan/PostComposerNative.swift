import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

final class CaptchaStorage {
    static let shared = CaptchaStorage()
    private init() {}
    var captchaId: String? = nil
}

struct PostComposerNative: View {
    let boardID: String
    let threadNo: Int?
    let threadTitle: String?
    let opTim: Int?

    init(boardID: String, threadNo: Int?, threadTitle: String? = nil, opTim: Int? = nil, initialComment: String? = nil) {
        self.boardID = boardID
        self.threadNo = threadNo
        self.threadTitle = threadTitle
        self.opTim = opTim
        _comment = State(initialValue: initialComment ?? "")
    }

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var subject: String = ""
    @State private var email: String = ""
    @State private var comment: String = ""


    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedData: Data? = nil
    @State private var selectedFilename: String? = nil

    @State private var captchaToken: String? = nil
    @State private var showingCaptcha = false
    @State private var isSolvingCaptcha = false
    
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
                Section(header: Text("Posting to /\(boardID)/")) {
                    if let threadNo {
                        Text("Replying to No. \(threadNo)")
                            .foregroundColor(.secondary)
                    } else {
                        Text("Creating a New Thread")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Identity (optional)")) {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }

                if threadNo == nil {
                    Section(header: Text("Subject (optional)")) {
                        TextField("Subject", text: $subject)
                            .autocorrectionDisabled()
                    }
                }

                Section(header: Text("Comment")) {
                    TextEditor(text: $comment)
                        .frame(minHeight: 180)
                }

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

                Section(header: Text("CAPTCHA"), footer: captchaStatusFooter) {
                    Button(action: {
                        errorMessage = nil
                        Task { await solveCaptchaPreferNative() }
                    }) {
                        if isSolvingCaptcha {
                            HStack { ProgressView(); Text("Solving...") }
                        } else if captchaToken == nil {
                            Text("Solve hCaptcha")
                        } else {
                            Text("Re-solve hCaptcha")
                        }
                    }
                    .disabled(isSolvingCaptcha)
                }

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

            .sheet(isPresented: $showingCaptcha) {
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
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }


    private var isFormInvalid: Bool {
        let hasText = !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = selectedData != nil
        
        let hasContent = hasText || hasImage
        return !hasContent || captchaToken == nil
    }

    private var captchaStatusFooter: some View {
        Text(captchaToken == nil ? "Required before posting." : "Token acquired ✓")
            .foregroundColor(captchaToken == nil ? .red : .green)
    }


    private func solveCaptchaPreferNative() async {
        await MainActor.run { isSolvingCaptcha = true }
        do {
            let (siteKey, baseURL) = try await CaptchaKeyResolver.fetchSiteKey(boardID: boardID, threadNo: threadNo)
            let token = try await HCaptchaSolver.solve(siteKey: siteKey, baseURL: baseURL)
            await MainActor.run {
                self.captchaToken = token
                self.isSolvingCaptcha = false
            }
        } catch {
            await MainActor.run {
                self.isSolvingCaptcha = false
                self.showingCaptcha = true
            }
        }
    }

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
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "bin"
                    
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

                let receipt = try await PostingManager.shared.submit(payload)

                await MainActor.run {
                    CaptchaStorage.shared.captchaId = nil

                    let resolvedThreadNo = receipt.threadNo ?? threadNo
                    if let resolvedThreadNo, let postNo = receipt.postNo {
                        let titleForYou: String? = {
                            if let threadTitle, !threadTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                return threadTitle
                            }
                            if self.threadNo == nil {
                                let sub = subject.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !sub.isEmpty { return sub }
                                let com = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                                return com.isEmpty ? nil : com
                            }
                            return nil
                        }()

                        YouPostsManager.shared.markYou(
                            boardID: boardID,
                            threadNo: resolvedThreadNo,
                            postNo: postNo,
                            threadTitle: titleForYou,
                            tim: opTim,
                            knownReplies: []
                        )
                    }

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
