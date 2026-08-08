package com.evgenyuliganets.file_image_cropper;

import android.graphics.Bitmap;
import android.graphics.ImageDecoder;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** System HEIC decoder and zero-copy-to-Rust bridge for Android. */
public final class FileImageCropperPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private MethodChannel channel;
  private final ExecutorService worker = Executors.newSingleThreadExecutor();
  private final Handler main = new Handler(Looper.getMainLooper());

  static {
    System.loadLibrary("file_image_cropper_heic_bridge");
  }

  private static native String[] nativeCropBitmap(
      Bitmap bitmap,
      byte[] outputPath,
      byte[] managedRoot,
      int regionType,
      double[] region,
      int[] options);

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    channel = new MethodChannel(binding.getBinaryMessenger(), "file_image_cropper/heic");
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    channel = null;
    worker.shutdown();
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    if (!call.method.equals("inspectHeic") && !call.method.equals("cropHeic")) {
      result.notImplemented();
      return;
    }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
      result.error("heic_android_version", "HEIC requires Android 9 (API 28) or newer.", null);
      return;
    }
    worker.execute(() -> {
      try {
        if (call.method.equals("inspectHeic")) {
          inspect(call, result);
        } else {
          crop(call, result);
        }
      } catch (Throwable error) {
        fail(result, "heic_decode", error.getMessage() == null ? error.toString() : error.getMessage());
      }
    });
  }

  private void inspect(MethodCall call, MethodChannel.Result result) throws Exception {
    final String inputPath = requiredString(call, "inputPath");
    final int[] dimensions = new int[2];
    final ImageDecoder.Source source = ImageDecoder.createSource(new File(inputPath));
    final Bitmap tiny = ImageDecoder.decodeBitmap(source, (decoder, info, ignored) -> {
      dimensions[0] = info.getSize().getWidth();
      dimensions[1] = info.getSize().getHeight();
      decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
      decoder.setTargetSize(1, 1);
    });
    tiny.recycle();
    final Map<String, Object> response = new HashMap<>();
    response.put("width", dimensions[0]);
    response.put("height", dimensions[1]);
    succeed(result, response);
  }

  private void crop(MethodCall call, MethodChannel.Result result) throws Exception {
    final String inputPath = requiredString(call, "inputPath");
    final ImageDecoder.Source source = ImageDecoder.createSource(new File(inputPath));
    final Bitmap decoded = ImageDecoder.decodeBitmap(source, (decoder, ignored, ignoredSource) -> {
      decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
      decoder.setMutableRequired(true);
      decoder.setUnpremultipliedRequired(true);
    });
    final Bitmap bitmap;
    if (decoded.getConfig() == Bitmap.Config.ARGB_8888) {
      bitmap = decoded;
    } else {
      bitmap = decoded.copy(Bitmap.Config.ARGB_8888, true);
      decoded.recycle();
      if (bitmap == null) {
        throw new IllegalStateException("Unable to convert HEIC pixels to RGBA8.");
      }
    }
    try {
      final String outputPath = call.argument("outputPath");
      final String[] nativeResult = nativeCropBitmap(
          bitmap,
          outputPath == null ? null : outputPath.getBytes(StandardCharsets.UTF_8),
          requiredString(call, "managedRoot").getBytes(StandardCharsets.UTF_8),
          requiredInt(call, "regionType"),
          new double[]{requiredDouble(call, "regionA"), requiredDouble(call, "regionB"),
              requiredDouble(call, "regionC"), requiredDouble(call, "regionD")},
          new int[]{requiredInt(call, "aspectPolicy"), requiredInt(call, "outputWidth"),
              requiredInt(call, "outputHeight"), requiredInt(call, "resizeFilter"),
              requiredInt(call, "outputFormat"), requiredInt(call, "jpegQuality"),
              requiredInt(call, "jpegBackgroundRed"), requiredInt(call, "jpegBackgroundGreen"),
              requiredInt(call, "jpegBackgroundBlue"), requiredBoolean(call, "webpLossless") ? 1 : 0,
              requiredInt(call, "webpQuality"), requiredBoolean(call, "overwrite") ? 1 : 0});
      final int status = Integer.parseInt(nativeResult[0]);
      if (status != 0) {
        fail(result, "native_" + status, "Rust crop failed (reason " + nativeResult[1] + ").");
        return;
      }
      final Map<String, Object> response = new HashMap<>();
      response.put("path", nativeResult[2]);
      response.put("isManaged", Boolean.parseBoolean(nativeResult[3]));
      succeed(result, response);
    } finally {
      bitmap.recycle();
    }
  }

  private void succeed(MethodChannel.Result result, Object value) {
    main.post(() -> result.success(value));
  }

  private void fail(MethodChannel.Result result, String code, String message) {
    main.post(() -> result.error(code, message, null));
  }

  private static String requiredString(MethodCall call, String name) {
    final String value = call.argument(name);
    if (value == null) throw new IllegalArgumentException("Missing " + name);
    return value;
  }

  private static int requiredInt(MethodCall call, String name) {
    final Number value = call.argument(name);
    if (value == null) throw new IllegalArgumentException("Missing " + name);
    return value.intValue();
  }

  private static double requiredDouble(MethodCall call, String name) {
    final Number value = call.argument(name);
    if (value == null) throw new IllegalArgumentException("Missing " + name);
    return value.doubleValue();
  }

  private static boolean requiredBoolean(MethodCall call, String name) {
    final Boolean value = call.argument(name);
    if (value == null) throw new IllegalArgumentException("Missing " + name);
    return value;
  }
}
