#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif
import CoreGraphics
import CoreImage
import ImageIO
#if SWIFT_PACKAGE
import file_image_cropper_bridge
#endif

public final class FileImageCropperPlugin: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(
    label: "file_image_cropper.heic",
    qos: .userInitiated
  )
  private let context = CIContext(options: [.cacheIntermediates: false])

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let binaryMessenger = registrar.messenger()
    #else
    let binaryMessenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(
      name: "file_image_cropper/heic",
      binaryMessenger: binaryMessenger
    )
    registrar.addMethodCallDelegate(FileImageCropperPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "inspectHeic" || call.method == "cropHeic" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let inputPath = arguments["inputPath"] as? String else {
      result(FlutterError(code: "invalid_arguments", message: "Missing inputPath.", details: nil))
      return
    }
    queue.async { [weak self] in
      autoreleasepool {
        do {
          let value: [String: Any]
          if call.method == "inspectHeic" {
            value = try Self.inspect(path: inputPath)
          } else {
            guard let self else { return }
            value = try self.crop(path: inputPath, arguments: arguments)
          }
          DispatchQueue.main.async { result(value) }
        } catch let error as PluginError {
          DispatchQueue.main.async {
            result(FlutterError(code: error.code, message: error.message, details: nil))
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "heic_decode", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  private static func inspect(path: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
      throw PluginError(code: "heic_decode", message: "Unable to read HEIC metadata.")
    }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let swapsAxes = (5...8).contains(orientation)
    return [
      "width": swapsAxes ? rawHeight.intValue : rawWidth.intValue,
      "height": swapsAxes ? rawWidth.intValue : rawHeight.intValue,
    ]
  }

  private func crop(path: String, arguments: [String: Any]) throws -> [String: Any] {
    guard let image = CIImage(
      contentsOf: URL(fileURLWithPath: path),
      options: [.applyOrientationProperty: true]
    ) else {
      throw PluginError(code: "heic_decode", message: "The system could not decode this HEIC image.")
    }
    let bounds = image.extent.integral
    guard bounds.width > 0, bounds.height > 0,
          bounds.width <= Double(UInt32.max), bounds.height <= Double(UInt32.max) else {
      throw PluginError(code: "heic_dimensions", message: "Invalid HEIC dimensions.")
    }
    let width = UInt32(bounds.width)
    let height = UInt32(bounds.height)
    let stride = Int(width) * 4
    guard stride / 4 == Int(width), Int(height) <= Int.max / stride else {
      throw PluginError(code: "heic_dimensions", message: "HEIC dimensions are too large.")
    }
    var pixels = [UInt8](repeating: 0, count: stride * Int(height))
    pixels.withUnsafeMutableBytes { bytes in
      context.render(
        image,
        toBitmap: bytes.baseAddress!,
        rowBytes: stride,
        bounds: bounds,
        format: .RGBA8,
        colorSpace: CGColorSpaceCreateDeviceRGB()
      )
    }

    var options = FICCropOptions()
    options.region_type = uint32(arguments, "regionType")
    options.aspect_policy = uint32(arguments, "aspectPolicy")
    options.region_a = double(arguments, "regionA")
    options.region_b = double(arguments, "regionB")
    options.region_c = double(arguments, "regionC")
    options.region_d = double(arguments, "regionD")
    options.output_width = uint32(arguments, "outputWidth")
    options.output_height = uint32(arguments, "outputHeight")
    options.resize_filter = uint32(arguments, "resizeFilter")
    options.output_format = uint32(arguments, "outputFormat")
    options.jpeg_quality = uint32(arguments, "jpegQuality")
    options.jpeg_background_red = uint32(arguments, "jpegBackgroundRed")
    options.jpeg_background_green = uint32(arguments, "jpegBackgroundGreen")
    options.jpeg_background_blue = uint32(arguments, "jpegBackgroundBlue")
    options.webp_lossless = (arguments["webpLossless"] as? Bool) == true ? 1 : 0
    options.webp_quality = uint32(arguments, "webpQuality")
    options.overwrite = (arguments["overwrite"] as? Bool) == true ? 1 : 0

    let outputPath = arguments["outputPath"] as? String
    guard let managedRoot = arguments["managedRoot"] as? String else {
      throw PluginError(code: "invalid_arguments", message: "Missing managedRoot.")
    }
    var resultPath = [UInt8](repeating: 0, count: 65_536)
    var resultLength = 0
    var isManaged: UInt8 = 0
    var reason: UInt32 = 0
    let pixelCount = pixels.count
    let resultCapacity = resultPath.count
    let outputBytes = outputPath.map { Array($0.utf8) } ?? []
    let rootBytes = Array(managedRoot.utf8)
    let outputLength = outputBytes.count
    let rootLength = rootBytes.count
    let status: Int32 = pixels.withUnsafeBytes { pixelBytes in
      resultPath.withUnsafeMutableBytes { resultBytes in
        outputBytes.withUnsafeBytes { outputBuffer in
          rootBytes.withUnsafeBytes { rootBuffer in
            fic_crop_rgba(
              pixelBytes.bindMemory(to: UInt8.self).baseAddress!, pixelCount,
              width, height, stride,
              outputBuffer.bindMemory(to: UInt8.self).baseAddress, outputLength,
              rootBuffer.bindMemory(to: UInt8.self).baseAddress, rootLength,
              &options,
              resultBytes.bindMemory(to: UInt8.self).baseAddress!, resultCapacity,
              &resultLength, &isManaged, &reason
            )
          }
        }
      }
    }
    guard status == 0 else {
      throw PluginError(
        code: "native_\(status)",
        message: "Rust crop failed (reason \(reason))."
      )
    }
    guard resultLength <= resultPath.count,
          let finalPath = String(bytes: resultPath.prefix(resultLength), encoding: .utf8) else {
      throw PluginError(code: "native_path", message: "Rust returned an invalid output path.")
    }
    return ["path": finalPath, "isManaged": isManaged != 0]
  }

  private func uint32(_ arguments: [String: Any], _ key: String) -> UInt32 {
    (arguments[key] as? NSNumber)?.uint32Value ?? 0
  }

  private func double(_ arguments: [String: Any], _ key: String) -> Double {
    (arguments[key] as? NSNumber)?.doubleValue ?? 0
  }
}

private struct PluginError: Error {
  let code: String
  let message: String
}
