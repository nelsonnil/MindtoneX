import AVFoundation
import SwiftUI

struct CardPracticeScanView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var session = CardSongSession.shared
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var lastText = ""
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            ZStack {
                CardCameraPreview(layer: $previewLayer)
                    .ignoresSafeArea()
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(OracleTheme.gold.opacity(0.9), lineWidth: 2)
                        .frame(height: 140)
                        .padding(.horizontal, 28)
                        .overlay(alignment: .bottom) {
                            Text("Hold card here · ALL CAPS · good light")
                                .font(.caption.weight(.semibold))
                                .padding(8)
                                .background(.black.opacity(0.55))
                                .clipShape(Capsule())
                                .padding(.bottom, 8)
                        }
                    if !lastText.isEmpty {
                        Text("Read: \(lastText)")
                            .font(.footnote)
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
                    }
                    Button {
                        Task { await runScan() }
                    } label: {
                        Text(scanning ? "Reading…" : "Scan now")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OracleTheme.goldGradient)
                            .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(scanning)
                    .padding()
                }
            }
            .navigationTitle("Practice scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                session.start(context: .test)
                previewLayer = session.makePreviewLayer()
            }
            .onDisappear {
                session.stopTest()
            }
        }
    }

    private func runScan() async {
        scanning = true
        defer { scanning = false }
        lastText = await session.practiceScanOnce()
        if lastText.isEmpty {
            PerformanceCues.cardScanFailed()
        } else {
            PerformanceCues.cardScanningPulse()
        }
    }
}

private struct CardCameraPreview: UIViewRepresentable {
    @Binding var layer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> PreviewView {
        PreviewView()
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer = layer
    }

    final class PreviewView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                guard let previewLayer else { return }
                previewLayer.frame = bounds
                layer.insertSublayer(previewLayer, at: 0)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
