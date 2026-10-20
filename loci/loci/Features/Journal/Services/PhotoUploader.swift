import Foundation
import ImageIO
import LociConnectProto
import UniformTypeIdentifiers

/// Journal photos are shrunk on the phone before upload: a photo is 3–6 MB
/// at 4032 px and the journal never shows one larger than a screen.
nonisolated enum ImageResize {
  static let maxEdge: CGFloat = 2048
  static let quality: CGFloat = 0.8

  /// The size that fits `size` within `maxEdge` on its long edge, never scaled up.
  static func fit(_ size: CGSize, maxEdge: CGFloat = maxEdge) -> CGSize {
    let long = max(size.width, size.height)
    guard long > 0 else { return .zero }
    let scale = min(1, maxEdge / long)
    return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
  }

  /// A JPEG of the image at most `maxEdge` on its long edge, upright. Only
  /// the pixels are written, so EXIF (GPS position included) is dropped.
  /// Nil when the data is not an image.
  static func jpeg(from data: Data, maxEdge: CGFloat = maxEdge, quality: CGFloat = quality) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxEdge,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let out = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return out as Data
  }
}

/// One photo upload: the server signs a PUT, the bytes go straight to
/// storage, and the server checks them before the photo shows. Any failure
/// after the signing removes the pending photo.
nonisolated struct PhotoUploader: Sendable {
  static let maxBytes = 8 * 1024 * 1024

  let service: any JournalService
  var session: URLSession = .shared

  /// URLSession sets these from the request itself.
  private static let transportHeaders: Set<String> = ["host", "content-length"]

  func upload(_ original: Data, to target: PhotoTarget, caption: String = "") async throws -> Loci_Journal_TripPhoto {
    guard let jpeg = ImageResize.jpeg(from: original) else { throw APIError.server("That file isn't a photo.") }
    guard jpeg.count <= Self.maxBytes else { throw APIError.server("That photo is too large.") }
    let ticket = try await service.createUpload(target, contentType: "image/jpeg", size: jpeg.count)
    do {
      var request = URLRequest(url: ticket.url)
      request.httpMethod = "PUT"
      for (name, value) in ticket.headers where !Self.transportHeaders.contains(name.lowercased()) {
        request.setValue(value, forHTTPHeaderField: name)
      }
      let (_, response) = try await session.upload(for: request, from: jpeg)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw APIError.server("The photo didn't upload.")
      }
      return try await service.confirm(photoID: ticket.photoID, caption: caption)
    } catch {
      try? await service.deletePhoto(id: ticket.photoID)
      throw error
    }
  }
}
