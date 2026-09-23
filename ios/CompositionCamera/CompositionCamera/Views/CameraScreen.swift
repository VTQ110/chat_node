import SwiftUI
import UIKit

struct CameraScreen: View {
    @StateObject private var camera = CameraService()
    @StateObject private var level = LevelMonitor()
    @Environment(\.scenePhase) private var scenePhase

    @State private var guide: CompositionGuide = .ruleOfThirds
    @State private var variant = 0
    @State private var smartGuideOn = true
    @State private var levelOn = true
    @State private var tipVisible = false
    @State private var flash = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            viewfinder
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipped()
            guidePicker
            Spacer(minLength: 0)
            bottomBar
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            camera.start()
            level.start()
        }
        .onDisappear {
            camera.stop()
            level.stop()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                camera.start()
                level.start()
            } else if phase == .background {
                camera.stop()
                level.stop()
            }
        }
        .task(id: guide) {
            // Show the tip for the newly selected guide for a few seconds.
            withAnimation { tipVisible = true }
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            withAnimation { tipVisible = false }
        }
        .task(id: camera.toastMessage) {
            guard camera.toastMessage != nil else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { camera.toastMessage = nil }
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        GeometryReader { geo in
            let frame = CGRect(origin: .zero, size: geo.size)
            let advice = currentAdvice(in: frame)

            ZStack {
                CameraPreviewView(camera: camera)
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            camera.focus(at: value.location)
                        }
                    )

                GuideOverlayView(guide: guide,
                                 variant: variant,
                                 subjectRect: smartGuideOn ? camera.subjectRect : nil,
                                 advice: advice)

                if levelOn && !level.isFlat {
                    LevelIndicatorView(rollDegrees: level.rollDegrees)
                }

                VStack {
                    if tipVisible {
                        banner(guide.tip, icon: "lightbulb", color: .white)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                    if let advice {
                        banner(advice.message,
                               icon: advice.arrow ?? "checkmark.circle.fill",
                               color: advice.isAligned ? .green : .yellow)
                    } else if smartGuideOn && guide != .none && camera.status == .running {
                        banner("Hướng camera vào chủ thể để nhận gợi ý bố cục",
                               icon: "viewfinder", color: .white.opacity(0.85))
                    }
                    if let toast = camera.toastMessage {
                        banner(toast, icon: "photo", color: .white)
                    }
                }
                .padding(10)
                .animation(.easeInOut(duration: 0.2), value: advice)

                if flash {
                    Color.white.allowsHitTesting(false)
                }

                statusOverlay
            }
        }
    }

    private func currentAdvice(in frame: CGRect) -> CompositionAdvice? {
        guard smartGuideOn, let subject = camera.subjectRect, let kind = camera.subjectKind else { return nil }
        return CompositionAdvisor.advice(subject: subject,
                                         kind: kind,
                                         focusPoints: guide.focusPoints(in: frame, variant: variant),
                                         frame: frame.size)
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch camera.status {
        case .unauthorized:
            VStack(spacing: 12) {
                Image(systemName: "camera.fill").font(.largeTitle)
                Text("Hãy cho phép truy cập camera trong Cài đặt để sử dụng ứng dụng.")
                    .multilineTextAlignment(.center)
                Button("Mở Cài đặt") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        case .failed:
            Text("Không khởi động được camera trên thiết bị này.")
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        case .idle, .running:
            EmptyView()
        }
    }

    private func banner(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.medium))
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Controls

    private var topBar: some View {
        HStack(spacing: 20) {
            toggleButton(icon: "wand.and.stars", isOn: smartGuideOn) { smartGuideOn.toggle() }
            toggleButton(icon: "level", isOn: levelOn) { levelOn.toggle() }
            Spacer()
            Text(guide.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Spacer()
            Button {
                variant = (variant + 1) % guide.variantCount
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundColor(guide.variantCount > 1 ? .white : .gray)
            }
            .disabled(guide.variantCount < 2)
            toggleButton(icon: "info.circle", isOn: tipVisible) {
                withAnimation { tipVisible.toggle() }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }

    private func toggleButton(icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isOn ? .yellow : .white)
        }
    }

    private var guidePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CompositionGuide.allCases) { item in
                        Button {
                            guide = item
                            variant = 0
                            withAnimation { proxy.scrollTo(item.id, anchor: .center) }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: item.icon).font(.system(size: 18))
                                Text(item.title).font(.caption2.weight(.semibold))
                            }
                            .frame(width: 72, height: 52)
                            .foregroundColor(item == guide ? .black : .white)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(item == guide ? Color.yellow : Color.white.opacity(0.12))
                            )
                        }
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Group {
                if let photo = camera.lastPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.12)
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            Button(action: takePhoto) {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle()
                        .fill(camera.isCapturing ? Color.gray : Color.white)
                        .frame(width: 62, height: 62)
                }
            }
            .disabled(camera.isCapturing || camera.status != .running)

            Spacer()

            Button {
                camera.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    private func takePhoto() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        camera.capturePhoto()
        flash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.25)) { flash = false }
        }
    }
}
