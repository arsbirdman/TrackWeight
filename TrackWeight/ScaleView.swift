//
//  ScaleView.swift
//  TrackWeight
//

import SwiftUI

struct ScaleView: View {
    @StateObject private var viewModel = ScaleViewModel()
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Weightpad")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Label(
                    viewModel.hasTouch ? "Live weight" : "Place your finger on the trackpad to begin",
                    systemImage: viewModel.hasTouch ? "circle.fill" : "hand.point.up.left"
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(viewModel.hasTouch ? Color.teal : Color.secondary)
            }

            WeightReadout(weight: viewModel.currentWeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 10) {
                Text("Press spacebar or click to zero")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Button(action: viewModel.zeroScale) {
                    Label("Zero Scale", systemImage: "arrow.clockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(.blue.gradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.hasTouch)
                .opacity(viewModel.hasTouch ? 1 : 0.4)
            }
        }
        .padding(24)
        .focusable()
        .modifier(FocusEffectModifier())
        .onAppear {
            viewModel.startListening()
            setupKeyMonitoring()
        }
        .onDisappear {
            viewModel.stopListening()
            removeKeyMonitoring()
        }
    }

    private func setupKeyMonitoring() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Space key code is 49
            if event.keyCode == 49 && viewModel.hasTouch {
                viewModel.zeroScale()
            }
            return event
        }
    }
    
    private func removeKeyMonitoring() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

// Share the same large, responsive display between the live scale and guided result.
struct WeightReadout: View {
    let weight: Float

    var body: some View {
        GeometryReader { geometry in
            let fontSize = min(geometry.size.width * 0.30, geometry.size.height * 0.70)

            VStack(spacing: 0) {
                Text(String(format: "%.1f", weight))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Weight")
                    .accessibilityValue("\(String(format: "%.1f", weight)) grams")

                Text("grams")
                    .font(.system(size: min(max(fontSize * 0.15, 18), 36), weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct FocusEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}

#Preview {
    ScaleView()
}
