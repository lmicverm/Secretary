import AVFoundation
import PDFKit
import PhotosUI
import SecretaryCore
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import VisionKit

struct ImportToolbarButtons: View {
    @EnvironmentObject private var store: LibraryStore

    @State private var showScanner = false
    @State private var showCamera = false
    @State private var showImporter = false
    @State private var showPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await openScanner() }
            } label: {
                Label("Scan", systemImage: "doc.viewfinder")
            }

            Menu {
                Button {
                    Task { await openScanner() }
                } label: {
                    Label("Scan with camera", systemImage: "doc.viewfinder")
                }
                Button {
                    showPhotos = true
                } label: {
                    Label("Import from Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import from Files", systemImage: "folder")
                }
            } label: {
                Label("Add", systemImage: "plus.circle.fill")
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentCameraRepresentable(
                onComplete: { data in
                    store.importData(data, hint: "letter-scan", pathExtension: "pdf")
                    store.statusMessage = "Scan added to Inbox"
                    showScanner = false
                },
                onCancel: { showScanner = false },
                onFail: { message in
                    showScanner = false
                    store.errorMessage = message
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureRepresentable(
                onCapture: { image in
                    if let data = pdfData(from: image) {
                        store.importData(data, hint: "camera-scan", pathExtension: "pdf")
                        store.statusMessage = "Photo scan added to Inbox"
                    } else {
                        store.errorMessage = "Couldn’t create a PDF from the photo."
                    }
                    showCamera = false
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showPhotos,
            selection: $photoItems,
            maxSelectionCount: 12,
            matching: .images
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: SecretaryUTTypes.importTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                store.importURLs(urls)
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
    }

    /// Public entry so the sidebar can trigger the same scan flow.
    func triggerScan() {
        Task { await openScanner() }
    }

    @MainActor
    private func openScanner() async {
        #if targetEnvironment(simulator)
        store.errorMessage = "Document scanning needs a real iPhone. Use Add → Photos or Files on the Simulator."
        return
        #else

        let permitted = await requestCameraAccess()
        guard permitted else {
            store.errorMessage = "Camera access is off. Enable it in Settings → Secretary → Camera."
            return
        }

        if VNDocumentCameraViewController.isSupported {
            showScanner = true
        } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        } else {
            store.errorMessage = "No camera available on this device. Use Add → Photos or Files."
        }
        #endif
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var imported = 0
        var failures = 0
        for item in items {
            do {
                guard let payload = try await loadPhotoData(from: item) else {
                    failures += 1
                    continue
                }
                await MainActor.run {
                    store.importData(payload.data, hint: "photo", pathExtension: payload.ext)
                }
                imported += 1
            } catch {
                failures += 1
            }
        }
        await MainActor.run {
            photoItems = []
            showPhotos = false
            if imported > 0 {
                store.statusMessage = "Imported \(imported) photo(s) to Inbox"
            }
            if failures > 0 && imported == 0 {
                store.errorMessage = "Couldn’t read the selected photo(s). Try Files instead."
            }
        }
    }

    private func loadPhotoData(from item: PhotosPickerItem) async throws -> (data: Data, ext: String)? {
        if let data = try await item.loadTransferable(type: Data.self), !data.isEmpty {
            return (data, preferredExtension(for: item) ?? "jpg")
        }
        if let raw = try await item.loadTransferable(type: ImportedImageData.self) {
            return (raw.data, raw.fileExtension)
        }
        return nil
    }

    private func preferredExtension(for item: PhotosPickerItem) -> String? {
        guard let type = item.supportedContentTypes.first else { return nil }
        if type.conforms(to: .png) { return "png" }
        if type.conforms(to: .heic) || type.identifier.contains("heic") { return "heic" }
        if type.conforms(to: .jpeg) { return "jpg" }
        return type.preferredFilenameExtension
    }

    private func pdfData(from image: UIImage) -> Data? {
        let pdf = PDFDocument()
        guard let page = PDFPage(image: image) else { return nil }
        pdf.insert(page, at: 0)
        return pdf.dataRepresentation()
    }
}

/// Standalone scan control for places without the full toolbar (sidebar, empty states).
struct ScanDocumentsButton: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var showScanner = false
    @State private var showCamera = false

    var body: some View {
        Button {
            Task { await open() }
        } label: {
            Label("Scan document", systemImage: "doc.viewfinder")
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentCameraRepresentable(
                onComplete: { data in
                    store.importData(data, hint: "letter-scan", pathExtension: "pdf")
                    store.statusMessage = "Scan added to Inbox"
                    showScanner = false
                },
                onCancel: { showScanner = false },
                onFail: { message in
                    showScanner = false
                    store.errorMessage = message
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureRepresentable(
                onCapture: { image in
                    let pdf = PDFDocument()
                    if let page = PDFPage(image: image), let data = {
                        pdf.insert(page, at: 0)
                        return pdf.dataRepresentation()
                    }() {
                        store.importData(data, hint: "camera-scan", pathExtension: "pdf")
                        store.statusMessage = "Photo scan added to Inbox"
                    } else {
                        store.errorMessage = "Couldn’t create a PDF from the photo."
                    }
                    showCamera = false
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
    }

    @MainActor
    private func open() async {
        #if targetEnvironment(simulator)
        store.errorMessage = "Document scanning needs a real iPhone."
        return
        #else
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let allowed: Bool
        switch status {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard allowed else {
            store.errorMessage = "Camera access is off. Enable it in Settings → Secretary → Camera."
            return
        }
        if VNDocumentCameraViewController.isSupported {
            showScanner = true
        } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        } else {
            store.errorMessage = "No camera available. Use Add → Photos or Files."
        }
        #endif
    }
}

struct DocumentCameraRepresentable: UIViewControllerRepresentable {
    var onComplete: (Data) -> Void
    var onCancel: () -> Void
    var onFail: (String) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentCameraRepresentable
        init(parent: DocumentCameraRepresentable) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pdf = PDFDocument()
            for i in 0..<scan.pageCount {
                if let page = PDFPage(image: scan.imageOfPage(at: i)) {
                    pdf.insert(page, at: pdf.pageCount)
                }
            }
            if let data = pdf.dataRepresentation() {
                parent.onComplete(data)
            } else {
                parent.onFail("Couldn’t save the scan as a PDF.")
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onFail(error.localizedDescription)
        }
    }
}

struct CameraCaptureRepresentable: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureRepresentable
        init(parent: CameraCaptureRepresentable) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            } else {
                parent.onCancel()
            }
        }
    }
}

struct ImportedImageData: Transferable {
    let data: Data
    let fileExtension: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .heic) { data in
            ImportedImageData(data: data, fileExtension: "heic")
        }
        DataRepresentation(importedContentType: .jpeg) { data in
            ImportedImageData(data: data, fileExtension: "jpg")
        }
        DataRepresentation(importedContentType: .png) { data in
            ImportedImageData(data: data, fileExtension: "png")
        }
        DataRepresentation(importedContentType: .image) { data in
            ImportedImageData(data: data, fileExtension: "jpg")
        }
    }
}
