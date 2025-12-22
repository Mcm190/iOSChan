import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $settings.colorScheme) {
                        ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                            Text(scheme.title).tag(scheme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Visibility")) {
                    Toggle("Show country flags", isOn: $settings.showFlags)
                    Toggle("Show poster IDs", isOn: $settings.showIDs)
                    Toggle("Show reply counts", isOn: $settings.showReplyCounts)
                    Toggle("Show image counts", isOn: $settings.showImageCounts)
                    Toggle("Highlight OP posts", isOn: $settings.highlightOP)
                }

                Section(header: Text("Layout")) {
                    Picker("Density", selection: Binding(
                        get: { settings.densityIndex },
                        set: { settings.densityIndex = $0 }
                    )) {
                        Text("Compact").tag(0)
                        Text("Comfortable").tag(1)
                        Text("Roomy").tag(2)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Thumbnail size")
                        Spacer()
                        Slider(value: $settings.thumbnailScale, in: 0.6...1.4, step: 0.05)
                    }

                    HStack {
                        Text("Font fine-tune")
                        Spacer()
                        Slider(value: $settings.fontFineTune, in: -1.0...1.0, step: 0.1)
                    }
                }

                Section(header: Text("Content Size")) {
                    Picker("Scale", selection: $settings.scale) {
                        ForEach(ContentScale.allCases, id: \.self) { scale in
                            Text(scale.title).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("XS")
                            .font(.caption2)
                            .frame(width: 24)
                        Slider(value: Binding(
                            get: { Double(settings.scaleIndex) },
                            set: { settings.scaleIndex = Int(round($0)) }
                        ), in: 0...Double(ContentScale.allCases.count - 1), step: 1)
                        .tint(.accentColor)
                        Text("N")
                            .font(.caption2)
                            .frame(width: 24)
                    }
                    .accessibilityLabel("Content size slider")
                }
                
                Section(header: Text("Cache"), footer: Text("Clearing caches keeps Favorites intact. Use 'Clear All (including Favorites cache)' to remove cached data including dead-thread markers.")) {
                    Button(role: .destructive) {
                        Task {
                            do { try CacheManager.clearCaches() } catch { print("Cache clear error: \(error)") }
                        }
                    } label: {
                        Label("Clear Cache (keep Favorites)", systemImage: "trash")
                    }

                    Button(role: .destructive) {
                        // Remove cached folders and also clear favorites dead markers
                        Task {
                            do { try CacheManager.clearCaches() } catch { print("Cache clear error: \(error)") }
                            // Also reset dead markers so everything looks fresh
                            FavoritesManager.shared.favorites = FavoritesManager.shared.favorites.map { fav in
                                var f = fav
                                f.isDead = nil
                                return f
                            }
                        }
                    } label: {
                        Label("Clear All (including Favorites cache)", systemImage: "trash.slash")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}

