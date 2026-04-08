//
//  ScanQRView.swift
//  UniMarket-Swift
//
//  NOTE: Add NSCameraUsageDescription to Info.plist before running on device.
//

import SwiftUI
import AVFoundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Main View

struct ScanQRView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scanState: ScanState = .scanning

    enum ScanState {
        case scanning
        case confirming(listingId: String, sellerId: String)
        case loading
        case confirmed
        case error(String)
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            switch scanState {
            case .scanning:
                scanningView
            case .confirming(let listingId, let sellerId):
                confirmingView(listingId: listingId, sellerId: sellerId)
            case .loading:
                loadingView
            case .confirmed:
                confirmedView
            case .error(let message):
                errorView(message: message)
            }
        }
    }

    // MARK: - States

    private var scanningView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Scan Pickup QR")
                    .font(.poppinsBold(22))
                    .foregroundStyle(AppTheme.primaryText)
                Text("Point your camera at the seller's QR code.")
                    .font(.poppinsRegular(13))
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            QRScannerRepresentable { code in
                handleScannedCode(code)
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.accent, lineWidth: 2)
            )

            Button("Cancel") { dismiss() }
                .font(.poppinsSemiBold(16))
                .foregroundStyle(.red)
        }
        .padding(24)
    }

    private func confirmingView(listingId: String, sellerId: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(AppTheme.accent)

            Text("QR Code Scanned")
                .font(.poppinsBold(22))
                .foregroundStyle(AppTheme.primaryText)

            Text("Confirm pickup for this listing?")
                .font(.poppinsRegular(14))
                .foregroundStyle(AppTheme.secondaryText)

            HStack(spacing: 12) {
                Button("Scan Again") { scanState = .scanning }
                    .font(.poppinsSemiBold(16))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accentAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button("Confirm") {
                    Task { await confirmPickup(listingId: listingId, sellerId: sellerId) }
                }
                .font(.poppinsSemiBold(16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(24)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(AppTheme.accent)
            Text("Confirming pickup...")
                .font(.poppinsRegular(14))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var confirmedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(AppTheme.accent)

            Text("Pickup Confirmed!")
                .font(.poppinsBold(24))
                .foregroundStyle(AppTheme.primaryText)

            Text("The meetup has been recorded successfully.")
                .font(.poppinsRegular(14))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)

            Button("Done") { dismiss() }
                .font(.poppinsSemiBold(16))
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accentAlt)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(24)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.red)

            Text("Something went wrong")
                .font(.poppinsBold(22))
                .foregroundStyle(AppTheme.primaryText)

            Text(message)
                .font(.poppinsRegular(13))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Try Again") { scanState = .scanning }
                    .font(.poppinsSemiBold(16))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accentAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button("Close") { dismiss() }
                    .font(.poppinsSemiBold(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(24)
    }

    // MARK: - Logic

    private func handleScannedCode(_ code: String) {
        guard
            let data = code.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
            let listingId = json["listingId"], !listingId.isEmpty,
            let sellerId = json["sellerId"], !sellerId.isEmpty
        else {
            scanState = .error("Invalid QR code. Please scan a valid UniMarket QR.")
            return
        }
        scanState = .confirming(listingId: listingId, sellerId: sellerId)
    }

    private func confirmPickup(listingId: String, sellerId: String) async {
        guard let buyerId = Auth.auth().currentUser?.uid else {
            await MainActor.run { scanState = .error("You must be logged in to confirm a pickup.") }
            return
        }
        await MainActor.run { scanState = .loading }
        do {
            try await Firestore.firestore().collection("meetup_transactions").addDocument(data: [
                "listingId": listingId,
                "sellerId": sellerId,
                "buyerId": buyerId,
                "status": "confirmed",
                "createdAt": FieldValue.serverTimestamp(),
                "confirmedAt": FieldValue.serverTimestamp()
            ])
            await MainActor.run { scanState = .confirmed }
        } catch {
            await MainActor.run { scanState = .error(error.localizedDescription) }
        }
    }
}

// MARK: - AVFoundation Scanner (UIViewControllerRepresentable)

struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasScanned = false
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupSession() {
        let session = AVCaptureSession()

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)

        captureSession = session
        previewLayer = preview
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard
            !hasScanned,
            let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            obj.type == .qr,
            let value = obj.stringValue
        else { return }

        hasScanned = true
        captureSession?.stopRunning()
        onScan?(value)
    }
}
