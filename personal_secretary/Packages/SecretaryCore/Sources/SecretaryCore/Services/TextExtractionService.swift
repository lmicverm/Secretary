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
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            #if canImport(AppKit)
            let image = NSImage(size: size)
            image.lockFocus()
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context)
                context.restoreGState()
            }
            image.unlockFocus()
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                parts.append(ocrCGImage(cgImage))
            }
            #elseif canImport(UIKit)
            let renderer = UIGraphicsImageRenderer(size: size)
            let uiImage = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            if let cgImage = uiImage.cgImage {
                parts.append(ocrCGImage(cgImage))
            }
            #endif
        }
        return parts.joined(separator: "\n")
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
