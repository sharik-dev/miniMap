import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(SpacesManager.self) private var manager

    var body: some View {
        ZStack {
            GlassmorphismBackground()

            if manager.spaces.isEmpty {
                Text("Loading spaces...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(manager.spaces) { space in
                            SpaceSegment(
                                space: space,
                                isActive: space.id == manager.activeSpaceID
                            )
                            .onTapGesture {
                                manager.switchToSpace(at: space.index)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(height: 50)
    }
}

struct SpaceSegment: View {
    let space: SpaceInfo
    let isActive: Bool

    var body: some View {
        HStack(spacing: 3) {
            if space.appIcons.isEmpty {
                Image(systemName: "square.dashed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(space.appIcons.indices, id: \.self) { i in
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: space.appIcons[i])
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        // Fullscreen badge
                        if space.isFullscreen {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(2)
                                .background(Color.blue.opacity(0.85), in: Circle())
                                .offset(x: 4, y: 4)
                        }
                    }
                    .padding(.bottom, space.isFullscreen ? 4 : 0)
                    .padding(.trailing, space.isFullscreen ? 4 : 0)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive
                    ? Color.white.opacity(0.25)
                    : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isActive
                                ? Color.white.opacity(0.6)
                                : Color.white.opacity(0.15),
                            lineWidth: isActive ? 1.5 : 0.5
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .help(space.isFullscreen
              ? "Fullscreen: \(space.appNames.first ?? "")"
              : space.appNames.joined(separator: ", "))
    }
}


struct GlassmorphismBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.25))

            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
