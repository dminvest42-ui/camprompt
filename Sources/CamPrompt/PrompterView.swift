import SwiftUI

/// The scrolling text content shown inside the floating notch panel.
struct PrompterView: View {
    let state: AppState
    @ObservedObject var settings: SettingsStore
    @ObservedObject var engine: ScrollEngine
    let topInset: CGFloat
    let pinned: Bool

    @State private var hovering = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            PanelShape(pinned: pinned)
                .fill(Color(hex: settings.bgColorHex).opacity(settings.bgOpacity))

            VStack(spacing: 0) {
                // The menu-bar / notch strip: keep it black so the panel
                // visually merges with the notch above it.
                if topInset > 0 {
                    Color.clear.frame(height: topInset)
                }
                textArea
            }

            if hovering {
                controlsHUD
            }
        }
        .clipShape(PanelShape(pinned: pinned))
        .onHover { hovering = $0 }
    }

    // MARK: - Text

    private var textArea: some View {
        GeometryReader { geo in
            let anchorY = geo.size.height * settings.anchorFraction
            ZStack(alignment: .topLeading) {
                Text(engine.text.isEmpty ? "Текст скрипта пуст.\nОткройте CamPrompt и напишите его." : engine.text)
                    .font(settings.font())
                    .foregroundColor(Color(hex: settings.textColorHex))
                    .lineSpacing(settings.lineSpacing)
                    .multilineTextAlignment(settings.textAlignment)
                    .frame(width: geo.size.width - CGFloat(settings.horizontalMargin) * 2,
                           alignment: settings.frameAlignment)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.preference(key: ContentHeightKey.self, value: textGeo.size.height)
                        }
                    )
                    .padding(.horizontal, CGFloat(settings.horizontalMargin))
                    .offset(y: anchorY - engine.offset)

                // Reading anchor line
                Rectangle()
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(height: 2)
                    .offset(y: anchorY - 4)
                    .padding(.horizontal, 6)
            }
            .scaleEffect(
                x: settings.mirrorHorizontal ? -1 : 1,
                y: settings.mirrorVertical ? -1 : 1
            )
            .onPreferenceChange(ContentHeightKey.self) { h in
                contentHeight = h
                engine.contentHeight = h
                engine.viewportHeight = geo.size.height
            }
        }
        .clipped()
    }

    // MARK: - HUD

    private var controlsHUD: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                hudButton(engine.isPlaying ? "pause.fill" : "play.fill") { engine.togglePlay() }
                hudButton("backward.end.fill") { engine.restart() }
                hudButton("minus") { settings.speed = max(1, settings.speed - 5) }
                Text("\(Int(settings.speed))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                hudButton("plus") { settings.speed = min(100, settings.speed + 5) }
                if state.recordingState == .recording {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text(timeString(state.recordingSeconds))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                }
                hudButton("xmark") { state.hidePanel() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 8)
        }
        .transition(.opacity)
    }

    private func hudButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Rounded only at the bottom when pinned to the notch (the top edge
/// touches the physical screen edge), rounded everywhere when floating.
struct PanelShape: Shape {
    let pinned: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 14
        if pinned {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                           control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                           control: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        } else {
            return Path(roundedRect: rect, cornerRadius: r)
        }
    }
}
