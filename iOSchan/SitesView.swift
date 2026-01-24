import SwiftUI

struct SitesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var siteDirectory = SiteDirectory.shared

    var body: some View {
        NavigationView {
            List(siteDirectory.all) { site in
                Button {
                    siteDirectory.switchTo(site)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Text(String(site.displayName.prefix(1)))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(site.displayName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            Text(site.baseURL.host ?? site.baseURL.absoluteString)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if site.id == siteDirectory.current.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sites")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
    }
}
