import SwiftUI

import Foundation

struct GalleryView: View {
    let mediaItems: [MediaItem]
    let onSelect: (Int) -> Void

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(mediaItems.enumerated()), id: \ .offset) { idx, item in
                        ZStack(alignment: .center) {
                            AsyncImage(url: item.thumbURL) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 120)
                                        .clipped()
                                } else {
                                    Color.gray.opacity(0.3).frame(height: 120)
                                }
                            }

                            if item.isVideo {
                                Image(systemName: "play.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                                    .shadow(radius: 3)
                            }
                        }
                        .onTapGesture { onSelect(idx) }
                    }
                }
                .padding(8)
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
