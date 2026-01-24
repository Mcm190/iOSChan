import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        NavigationView {
            List {
                Section {
                    Picker("Theme", selection: $settings.colorScheme) {
                        ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                            Text(scheme.title).tag(scheme)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Appearance", systemImage: "paintbrush")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }

                Section {
                    Toggle("Show country flags", isOn: $settings.showFlags)
                    Toggle("Show poster IDs", isOn: $settings.showIDs)
                    Toggle("Show reply counts", isOn: $settings.showReplyCounts)
                    Toggle("Show image counts", isOn: $settings.showImageCounts)
                    Toggle("Highlight OP posts", isOn: $settings.highlightOP)
                } header: {
                    Label("Visibility", systemImage: "eye")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }

                Section {
                    Picker("Density", selection: Binding(
                        get: { settings.densityIndex },
                        set: { settings.densityIndex = $0 }
                    )) {
                        Text("Compact").tag(0)
                        Text("Comfortable").tag(1)
                        Text("Roomy").tag(2)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Thumbnail size")
                            .font(.subheadline)
                        Slider(value: $settings.thumbnailScale, in: 0.6...1.4, step: 0.05)
                            .tint(.accentColor)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Font adjustment")
                            .font(.subheadline)
                        Slider(value: $settings.fontFineTune, in: -1.0...1.0, step: 0.1)
                            .tint(.accentColor)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Layout", systemImage: "square.grid.2x2")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }

                Section {
                    Picker("Scale", selection: $settings.scale) {
                        ForEach(ContentScale.allCases, id: \.self) { scale in
                            Text(scale.title).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("XS")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 24)
                        Slider(value: Binding(
                            get: { Double(settings.scaleIndex) },
                            set: { settings.scaleIndex = Int(round($0)) }
                        ), in: 0...Double(ContentScale.allCases.count - 1), step: 1)
                        .tint(.accentColor)
                        Text("N")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 24)
                    }
                } header: {
                    Label("Content Size", systemImage: "textformat.size")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            do { try CacheManager.clearCaches() } catch { print("Cache clear error: \(error)") }
                        }
                    } label: {
                        Label("Clear Cache", systemImage: "trash")
                    }

                    Button(role: .destructive) {
                        Task {
                            do { try CacheManager.clearCaches() } catch { print("Cache clear error: \(error)") }
                            FavoritesManager.shared.favorites = FavoritesManager.shared.favorites.map { fav in
                                var f = fav
                                f.isDead = nil
                                return f
                            }
                        }
                    } label: {
                        Label("Clear All Data", systemImage: "trash.slash")
                    }
                } header: {
                    Label("Storage", systemImage: "internaldrive")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(nil)
                } footer: {
                    Text("Clearing cache keeps your favorites intact. Use 'Clear All Data' to also remove dead-thread markers.")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
