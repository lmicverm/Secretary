import CoreGraphics
import Foundation
import PDFKit
import Vision
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Extracts searchable text from PDFs and images using PDFKit + Vision OCR.
public enum TextExtractionService {
    public static let recognitionLanguages = ["nl-NL", "nl-BE", "fr-FR", "en-US"]

    public static func extractText(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            let pdfText = extractPDFText(from: url)
            // Prefer embedded text when present; otherwise OCR scanned pages.
            if pdfText.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
                return pdfText
            }
            let ocr = ocrPDFPages(from: url)
            return ocr.isEmpty ? pdfText : ocr
        }
        if ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(ext) {
            return ocrImage(at: url)
        }
        if ["txt", "md", "csv", "json", "html", "htm", "xml"].contains(ext) {
            return (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1))
                ?? ""
        }
        // Last resort: try reading as UTF-8 text for unknown types
        if let text = try? String(contentsOf: url, encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).count > 10,
           !text.contains("\0") {
            return text
        }
        return ""
    }

    public static func extractPDFText(from url: URL) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var parts: [String] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i), let text = page.string else { continue }
            parts.append(text)
        }
        return parts.joined(separator: "\n")
    }

    public static func ocrPDFPages(from url: URL, maxPages: Int = 10) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var parts: [String] = []
        let count = min(document.pageCount, maxPages)
        for i in 0..<count {
            guard let page = document.page(at: i) else { continue }
            // lockFocus() aborts off the main thread or on a zero-size image.
            // Rasterize into a CG bitmap instead so import-time OCR cannot crash.
            guard let cgImage = rasterizePDFPage(page) else { continue }
            parts.append(ocrCGImage(cgImage))
        }
        return parts.joined(separator: "\n")
    }

    private static func rasterizePDFPage(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let width = Int((bounds.width * scale).rounded(.down))
        let height = Int((bounds.height * scale).rounded(.down))
        guard width >= 1, height >= 1 else {
            NSLog("Secretary: skip OCR raster for empty PDF page")
            return nil
        }
        guard width <= 4096, height <= 4096 else {
            NSLog("Secretary: skip OCR raster for oversized PDF page \(width)x\(height)")
            return nil
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }

    public static func ocrImage(at url: URL) -> String {
        #if canImport(AppKit)
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ocrWithVisionRequest(url: url)
        }
        return ocrCGImage(cgImage)
        #elseif canImport(UIKit)
        guard let image = UIImage(contentsOfFile: url.path), let cgImage = image.cgImage else {
            return ocrWithVisionRequest(url: url)
        }
        return ocrCGImage(cgImage)
        #else
        return ocrWithVisionRequest(url: url)
        #endif
    }

    public static func ocrCGImage(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    private static func ocrWithVisionRequest(url: URL) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages
        let handler = VNImageRequestHandler(url: url, options: [:])
        do {
            try handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } catch {
            return ""
        }
    }
}
