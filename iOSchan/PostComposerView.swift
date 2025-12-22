import SwiftUI

struct PostComposerView: View {
    let boardID: String
    let threadNo: Int?   // nil = new thread, otherwise reply
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var subject: String = ""
    @State private var comment: String = ""
    
    @State private var showWebPost = false
    @State private var showCopiedToast = false
    
    private var isReply: Bool { threadNo != nil }
    
    private var titleText: String {
        isReply ? "Reply" : "New Thread"
    }
    
    private var postURL: URL {
        if let threadNo {
            // Reply: open the thread page
            return URL(string: "https://boards.4chan.org/\(boardID)/thread/\(threadNo)")!
        } else {
            // New thread: open the board page (NOT /post)
            return URL(string: "https://boards.4chan.org/\(boardID)/")!
        }
    }

    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Posting to /\(boardID)/")) {
                    if let threadNo {
                        Text("Replying to thread \(threadNo)")
                            .foregroundColor(.secondary)
                    } else {
                        Text("Creating a new thread")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Identity (optional)")) {
                    TextField("Name (optional)", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                if !isReply {
                    Section(header: Text("Subject (optional)")) {
                        TextField("Subject", text: $subject)
                            .autocorrectionDisabled()
                    }
                }
                
                Section(header: Text("Comment")) {
                    TextEditor(text: $comment)
                        .frame(minHeight: 180)
                }
                
                Section {
                    Button {
                        UIPasteboard.general.string = comment
                        showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            showCopiedToast = false
                        }
                    } label: {
                        Label("Copy Comment", systemImage: "doc.on.doc")
                    }
                    .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button {
                        showWebPost = true
                    } label: {
                        Label("Open Post Form (Safari)", systemImage: "paperplane.fill")
                    }
                    .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Safari is used for maximum compatibility with CAPTCHA and site protections. Copy your comment, then paste it into the form.")
                }
            }
            .navigationTitle(titleText)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                if showCopiedToast {
                    Text("Copied ✓")
                        .font(.caption.bold())
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showCopiedToast)
            .sheet(isPresented: $showWebPost) {
                PostWebView(
                    boardID: boardID,
                    threadNo: threadNo,
                    prefillName: name,
                    prefillSubject: subject,
                    prefillComment: comment
                )
            }

        }
    }
}

