import SwiftUI
import AVFoundation
import AudioToolbox

public struct QRCodeScannerView: View {
    public let onScanned: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var hasScanned: Bool = false

    public init(onScanned: @escaping (String, String) -> Void) {
        self.onScanned = onScanned
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                EditorialColor.paper
                    .ignoresSafeArea()

                if let errorMessage {
                    VStack(spacing: EditorialSpacing.medium) {
                        Image(systemName: "camera.badge.ellipsis")
                            .font(.system(size: 48))
                            .foregroundStyle(EditorialColor.secondaryInk)

                        Text("Camera Unavailable")
                            .font(.editorialTitle)
                            .foregroundStyle(EditorialColor.ink)

                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(EditorialColor.secondaryInk)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, EditorialSpacing.large)

                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(EditorialButtonStyle(isPrimary: true))
                        .padding(.top, EditorialSpacing.medium)
                    }
                    .padding()
                } else {
                    CameraScannerRepresentable { code in
                        guard !hasScanned else { return }
                        handleScannedCode(code)
                    } onError: { error in
                        errorMessage = error
                    }
                    .ignoresSafeArea()

                    // Viewfinder overlay
                    VStack {
                        VStack(spacing: EditorialSpacing.compact) {
                            Text("HERMES / DIRECT PAIRING")
                                .font(.editorialUtilitySmall)
                                .foregroundStyle(EditorialColor.paper)
                                .padding(.horizontal, EditorialSpacing.compact)
                                .padding(.vertical, 4)
                                .background(EditorialColor.ink)

                            Text("Point your camera at the QR code rendered in the host terminal.")
                                .font(.footnote)
                                .foregroundStyle(EditorialColor.paper)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, EditorialSpacing.large)
                                .shadow(radius: 2)
                        }
                        .padding(.top, EditorialSpacing.hero)

                        Spacer()

                        // Viewfinder Box
                        ZStack {
                            CutCornerShape(cut: 20)
                                .stroke(EditorialColor.paper, lineWidth: 2)
                                .frame(width: 250, height: 250)
                                .shadow(radius: 8)

                            CutCornerShape(cut: 20)
                                .stroke(EditorialColor.ink.opacity(0.3), lineWidth: 1)
                                .frame(width: 246, height: 246)
                        }

                        Spacer()

                        Button(action: { dismiss() }) {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .buttonStyle(EditorialButtonStyle(isPrimary: false))
                        .padding(.bottom, EditorialSpacing.hero)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(EditorialColor.ink)
                }
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        hasScanned = true
        guard let data = code.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let endpoint = json["endpoint"] as? String,
              let token = json["token"] as? String else {
            hasScanned = false
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onScanned(endpoint, token)
        dismiss()
    }
}

private struct CameraScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> CameraScannerViewController {
        let vc = CameraScannerViewController()
        vc.onCodeScanned = onCodeScanned
        vc.onError = onError
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraScannerViewController, context: Context) {}
}

private final class CameraScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }

    private func setupCamera() {
        #if targetEnvironment(simulator)
        onError?("Camera is unavailable in the iOS Simulator. Please enter the endpoint URL and token manually.")
        return
        #endif

        let session = AVCaptureSession()
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            onError?("No video camera is available on this device.")
            return
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            onError?("Could not initialize camera input. Check Privacy permissions.")
            return
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            onError?("Could not add camera input to capture session.")
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            onError?("Could not configure QR code metadata output.")
            return
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        self.captureSession = session
        self.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringVal = object.stringValue else {
            return
        }
        onCodeScanned?(stringVal)
    }
}
