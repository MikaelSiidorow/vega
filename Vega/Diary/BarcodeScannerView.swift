import AVFoundation
import SwiftUI
import VisionKit

enum BarcodeScannerMode: Equatable {
    case camera
    case fixture(ProductBarcode)
    case unavailable(String)
}

private struct BarcodeScannerModeKey: EnvironmentKey {
    static let defaultValue = BarcodeScannerMode.camera
}

extension EnvironmentValues {
    var barcodeScannerMode: BarcodeScannerMode {
        get { self[BarcodeScannerModeKey.self] }
        set { self[BarcodeScannerModeKey.self] = newValue }
    }
}

struct BarcodeScannerView: View {
    let mode: BarcodeScannerMode
    let onScan: (ProductBarcode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase = CameraPhase.checking
    @State private var manualCode = ""
    @State private var scannerMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if phase == .manual {
                    manualEntry
                } else {
                    switch mode {
                    case .fixture(let barcode):
                        fixtureScanner(barcode)
                    case .camera:
                        cameraContent
                    case .unavailable(let message):
                        unavailableContent(message)
                    }
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancel-barcode-scanner")
                }
            }
        }
        .task {
            guard mode == .camera else { return }
            await prepareCamera()
        }
    }

    @ViewBuilder
    private var cameraContent: some View {
        switch phase {
        case .checking:
            ProgressView("Preparing camera…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .scanning:
            scannerSurface
        case .manual:
            manualEntry
        case .unavailable(let message):
            unavailableContent(message)
        }
    }

    private func unavailableContent(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Scanner unavailable", systemImage: "camera.fill")
        } description: {
            Text(message)
        } actions: {
            Button("Enter code manually") {
                phase = .manual
            }
            .accessibilityIdentifier("manual-barcode-fallback")
        }
    }

    private var scannerSurface: some View {
        ZStack(alignment: .bottom) {
            VisionKitBarcodeScanner(
                onRecognition: accept,
                onFailure: { error in
                    phase = .unavailable(
                        error.localizedDescription.isEmpty
                            ? "The camera scanner stopped unexpectedly."
                            : error.localizedDescription
                    )
                }
            )
            .ignoresSafeArea(edges: .bottom)

            scannerControls
        }
    }

    private func fixtureScanner(_ barcode: ProductBarcode) -> some View {
        ZStack(alignment: .bottom) {
            Color.black
                .overlay {
                    VStack(spacing: 16) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 72, weight: .thin))
                        Text("Camera preview")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                }
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                Text("Center the product barcode in the frame.")
                    .multilineTextAlignment(.center)
                Button("Simulate barcode scan") {
                    accept(barcode.value)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("simulate-barcode-scan")
                Button("Enter code manually") {
                    phase = .manual
                }
                .accessibilityIdentifier("manual-barcode-fallback")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .accessibilityIdentifier("barcode-scanner")
    }

    private var scannerControls: some View {
        VStack(spacing: 12) {
            Text(scannerMessage ?? "Center the product barcode in the frame.")
                .multilineTextAlignment(.center)
                .foregroundStyle(scannerMessage == nil ? Color.primary : Color.red)
            Button("Enter code manually") {
                phase = .manual
            }
            .accessibilityIdentifier("manual-barcode-fallback")
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var manualEntry: some View {
        Form {
            Section("Product code") {
                TextField("EAN, UPC, or GTIN", text: $manualCode)
                    .keyboardType(.numberPad)
                    .textContentType(.none)
                    .accessibilityIdentifier("manual-barcode-code")
            }

            if !manualCode.isEmpty, ProductBarcode(manualCode) == nil {
                Section {
                    Text("Enter an 8-, 12-, 13-, or 14-digit product code.")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Search for product") {
                    guard let barcode = ProductBarcode(manualCode) else { return }
                    onScan(barcode)
                    dismiss()
                }
                .disabled(ProductBarcode(manualCode) == nil)
                .accessibilityIdentifier("submit-manual-barcode")
            }
        }
        .accessibilityIdentifier("manual-barcode-entry")
    }

    private func prepareCamera() async {
        guard DataScannerViewController.isSupported else {
            phase = .unavailable("This device does not support live barcode scanning.")
            return
        }

        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            authorized = false
        @unknown default:
            authorized = false
        }

        guard authorized else {
            phase = .unavailable(
                "Camera access is off. Allow it in Settings or enter the code manually."
            )
            return
        }
        guard DataScannerViewController.isAvailable else {
            phase = .unavailable(
                "The camera is currently unavailable. Enter the code manually or try again later."
            )
            return
        }
        phase = .scanning
    }

    private func accept(_ candidate: String) {
        guard let barcode = ProductBarcode(candidate) else {
            scannerMessage = "That isn’t a supported EAN, UPC, or GTIN code."
            return
        }
        onScan(barcode)
        dismiss()
    }
}

private enum CameraPhase: Equatable {
    case checking
    case scanning
    case manual
    case unavailable(String)
}

private struct VisionKitBarcodeScanner: UIViewControllerRepresentable {
    let onRecognition: (String) -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecognition: onRecognition, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning, !context.coordinator.requestedStart else { return }
        context.coordinator.requestedStart = true
        do {
            try scanner.startScanning()
        } catch {
            context.coordinator.onFailure(error)
        }
    }

    static func dismantleUIViewController(
        _ scanner: DataScannerViewController,
        coordinator: Coordinator
    ) {
        scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onRecognition: (String) -> Void
        let onFailure: (Error) -> Void
        var requestedStart = false
        private var gate = BarcodeScanGate()

        init(
            onRecognition: @escaping (String) -> Void,
            onFailure: @escaping (Error) -> Void
        ) {
            self.onRecognition = onRecognition
            self.onFailure = onFailure
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard case .barcode(let observation) = item,
                    let payload = observation.payloadStringValue,
                    let barcode = gate.accept(payload)
                else { continue }
                dataScanner.stopScanning()
                onRecognition(barcode.value)
                return
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            onFailure(error)
        }
    }
}
