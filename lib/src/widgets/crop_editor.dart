import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ffi/native_image_engine.dart';
import '../models/crop_region.dart';
import '../models/image_info.dart' as cropper;
import 'crop_editor_controller.dart';
import 'crop_overlay_style.dart';

typedef CropEditorImageBuilder =
    Widget Function(
      BuildContext context,
      File input,
      cropper.ImageInfo imageInfo,
    );

typedef CropEditorLoadingBuilder = Widget Function(BuildContext context);

typedef CropEditorErrorBuilder =
    Widget Function(BuildContext context, Object error, VoidCallback retry);

typedef CropEditorOverlayBuilder =
    Widget Function(BuildContext context, CropEditorOverlayDetails details);

enum CropEditorInteractionMode {
  /// Drag the crop area and its handles.
  select,

  /// Pan and zoom the complete image/selection canvas for precise editing.
  panAndZoom,
}

/// Geometry exposed to a custom overlay builder.
final class CropEditorOverlayDetails {
  const CropEditorOverlayDetails({
    required this.imageRect,
    required this.cropRect,
    required this.region,
    required this.style,
  });

  final Rect imageRect;
  final Rect cropRect;
  final NormalizedCropRegion region;
  final CropOverlayStyle style;
}

/// Interactive crop selection body without any app bar or action buttons.
class CropEditor extends StatefulWidget {
  const CropEditor({
    required this.input,
    this.imageInfo,
    this.controller,
    this.aspectRatio,
    this.initializeToAspectRatio = true,
    this.enabled = true,
    this.allowMove = true,
    this.allowResize = true,
    this.allowNewSelection = true,
    this.interactionMode = CropEditorInteractionMode.select,
    this.transformationController,
    this.minScale = 1,
    this.maxScale = 8,
    this.boundaryMargin = EdgeInsets.zero,
    this.panAxis = PanAxis.free,
    this.scaleFactor = 200,
    this.transformationAlignment,
    this.trackpadScrollCausesScale = false,
    this.interactionEndFrictionCoefficient = 0.0000135,
    this.onInteractionStart,
    this.onInteractionUpdate,
    this.onInteractionEnd,
    this.minCropSize = 48,
    this.padding = EdgeInsets.zero,
    this.backgroundColor = Colors.black,
    this.overlayStyle = const CropOverlayStyle(),
    this.showDefaultOverlay = true,
    this.imageBuilder,
    this.overlayBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.onChanged,
    this.semanticLabel = 'Image crop editor',
    this.clipBehavior = Clip.hardEdge,
    super.key,
  }) : assert(aspectRatio == null || aspectRatio > 0),
       assert(minCropSize > 0),
       assert(minScale > 0),
       assert(maxScale >= minScale),
       assert(interactionEndFrictionCoefficient > 0);

  final File input;
  final cropper.ImageInfo? imageInfo;
  final CropEditorController? controller;

  /// Locks the selection to this physical-pixel aspect ratio when non-null.
  final double? aspectRatio;

  /// Centers a full initial selection to [aspectRatio] after metadata loads.
  final bool initializeToAspectRatio;
  final bool enabled;
  final bool allowMove;
  final bool allowResize;
  final bool allowNewSelection;
  final CropEditorInteractionMode interactionMode;
  final TransformationController? transformationController;
  final double minScale;
  final double maxScale;
  final EdgeInsets boundaryMargin;
  final PanAxis panAxis;
  final double scaleFactor;
  final Alignment? transformationAlignment;
  final bool trackpadScrollCausesScale;
  final double interactionEndFrictionCoefficient;
  final GestureScaleStartCallback? onInteractionStart;
  final GestureScaleUpdateCallback? onInteractionUpdate;
  final GestureScaleEndCallback? onInteractionEnd;
  final double minCropSize;
  final EdgeInsets padding;
  final Color backgroundColor;
  final CropOverlayStyle overlayStyle;
  final bool showDefaultOverlay;
  final CropEditorImageBuilder? imageBuilder;
  final CropEditorOverlayBuilder? overlayBuilder;
  final CropEditorLoadingBuilder? loadingBuilder;
  final CropEditorErrorBuilder? errorBuilder;
  final ValueChanged<NormalizedCropRegion>? onChanged;
  final String semanticLabel;
  final Clip clipBehavior;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  late CropEditorController _controller;
  late bool _ownsController;
  late TransformationController _transformationController;
  late bool _ownsTransformationController;
  cropper.ImageInfo? _imageInfo;
  Object? _error;
  int _loadGeneration = 0;
  _DragHandle? _dragHandle;
  Offset? _dragStartPoint;
  Rect? _dragStartRect;
  Rect? _dragImageRect;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
    _attachTransformationController(widget.transformationController);
    _loadImageInfo();
  }

  @override
  void didUpdateWidget(CropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController();
      _attachController(widget.controller);
    }
    if (oldWidget.transformationController != widget.transformationController) {
      _detachTransformationController();
      _attachTransformationController(widget.transformationController);
    }
    if (oldWidget.input.path != widget.input.path ||
        oldWidget.imageInfo != widget.imageInfo) {
      _loadImageInfo();
    } else if (oldWidget.aspectRatio != widget.aspectRatio &&
        widget.initializeToAspectRatio) {
      _initializeAspectSelection(force: true);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _detachController();
    _detachTransformationController();
    super.dispose();
  }

  void _attachController(CropEditorController? supplied) {
    _ownsController = supplied == null;
    _controller = supplied ?? CropEditorController();
    _controller.addListener(_handleControllerChanged);
  }

  void _detachController() {
    _controller.removeListener(_handleControllerChanged);
    if (_ownsController) _controller.dispose();
  }

  void _attachTransformationController(TransformationController? supplied) {
    _ownsTransformationController = supplied == null;
    _transformationController = supplied ?? TransformationController();
    _transformationController.addListener(_handleTransformationChanged);
  }

  void _detachTransformationController() {
    _transformationController.removeListener(_handleTransformationChanged);
    if (_ownsTransformationController) _transformationController.dispose();
  }

  void _handleTransformationChanged() {
    if (mounted) setState(() {});
  }

  void _handleControllerChanged() {
    widget.onChanged?.call(_controller.region);
    if (mounted) setState(() {});
  }

  Future<void> _loadImageInfo() async {
    final int generation = ++_loadGeneration;
    setState(() {
      _imageInfo = widget.imageInfo;
      _error = null;
    });
    if (widget.imageInfo != null) {
      _initializeAspectSelection();
      return;
    }
    try {
      final cropper.ImageInfo info = await const NativeImageEngine()
          .inspectImage(widget.input);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _imageInfo = info);
      _initializeAspectSelection();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    }
  }

  void _initializeAspectSelection({bool force = false}) {
    final cropper.ImageInfo? info = _imageInfo;
    final double? ratio = widget.aspectRatio;
    if (!widget.initializeToAspectRatio ||
        info == null ||
        ratio == null ||
        (!force && !_isFullRegion(_controller.region))) {
      return;
    }
    final double imageRatio = info.orientedWidth / info.orientedHeight;
    if (imageRatio > ratio) {
      final double width = ratio / imageRatio;
      _controller.setResetRegion(
        NormalizedCropRegion(
          left: (1 - width) / 2,
          top: 0,
          width: width,
          height: 1,
        ),
      );
    } else {
      final double height = imageRatio / ratio;
      _controller.setResetRegion(
        NormalizedCropRegion(
          left: 0,
          top: (1 - height) / 2,
          width: 1,
          height: height,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Object? error = _error;
    if (error != null) {
      return ColoredBox(
        color: widget.backgroundColor,
        child:
            widget.errorBuilder?.call(context, error, _loadImageInfo) ??
            _DefaultCropEditorError(error: error, retry: _loadImageInfo),
      );
    }
    final cropper.ImageInfo? info = _imageInfo;
    if (info == null) {
      return ColoredBox(
        color: widget.backgroundColor,
        child:
            widget.loadingBuilder?.call(context) ??
            const Center(child: CircularProgressIndicator()),
      );
    }

    return Semantics(
      label: widget.semanticLabel,
      child: ColoredBox(
        color: widget.backgroundColor,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size viewportSize = constraints.biggest;
            if (!viewportSize.width.isFinite ||
                !viewportSize.height.isFinite ||
                viewportSize.isEmpty) {
              return const SizedBox.shrink();
            }
            final Rect contentRect = Rect.fromLTRB(
              widget.padding.left,
              widget.padding.top,
              viewportSize.width - widget.padding.right,
              viewportSize.height - widget.padding.bottom,
            );
            if (contentRect.isEmpty) return const SizedBox.shrink();
            final Size contentSize = contentRect.size;
            final Rect baseImageRect = _containRect(
              contentSize,
              Size(
                info.orientedWidth.toDouble(),
                info.orientedHeight.toDouble(),
              ),
            );
            final Rect imageRect = _transformRect(
              baseImageRect,
              _transformationController.value,
              widget.transformationAlignment,
              contentSize,
            ).shift(contentRect.topLeft);
            final Rect cropRect = _transformRect(
              _rectForRegion(baseImageRect, _controller.region),
              _transformationController.value,
              widget.transformationAlignment,
              contentSize,
            ).shift(contentRect.topLeft);
            final CropEditorOverlayDetails overlayDetails =
                CropEditorOverlayDetails(
                  imageRect: imageRect,
                  cropRect: cropRect,
                  region: _controller.region,
                  style: widget.overlayStyle,
                );
            final Widget imageCanvas = Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned.fromRect(
                  rect: baseImageRect,
                  child:
                      widget.imageBuilder?.call(context, widget.input, info) ??
                      Image.file(
                        widget.input,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.high,
                      ),
                ),
              ],
            );
            final Widget selectionLayer = IgnorePointer(
              ignoring:
                  !widget.enabled ||
                  widget.interactionMode ==
                      CropEditorInteractionMode.panAndZoom,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (DragStartDetails details) =>
                    _startDrag(details, imageRect, cropRect),
                onPanUpdate: _updateDrag,
                onPanEnd: (_) => _endDrag(),
                onPanCancel: _endDrag,
                onDoubleTap: _resetEditor,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (widget.showDefaultOverlay)
                      CustomPaint(painter: _CropOverlayPainter(overlayDetails)),
                    if (widget.overlayBuilder case final builder?)
                      Positioned.fill(child: builder(context, overlayDetails)),
                  ],
                ),
              ),
            );
            return ClipRect(
              clipBehavior: widget.clipBehavior,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Positioned.fromRect(
                    rect: contentRect,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      panEnabled:
                          widget.enabled &&
                          widget.interactionMode ==
                              CropEditorInteractionMode.panAndZoom,
                      scaleEnabled:
                          widget.enabled &&
                          widget.interactionMode ==
                              CropEditorInteractionMode.panAndZoom,
                      minScale: widget.minScale,
                      maxScale: widget.maxScale,
                      boundaryMargin: widget.boundaryMargin,
                      panAxis: widget.panAxis,
                      scaleFactor: widget.scaleFactor,
                      alignment: widget.transformationAlignment,
                      trackpadScrollCausesScale:
                          widget.trackpadScrollCausesScale,
                      interactionEndFrictionCoefficient:
                          widget.interactionEndFrictionCoefficient,
                      onInteractionStart: widget.onInteractionStart,
                      onInteractionUpdate: widget.onInteractionUpdate,
                      onInteractionEnd: widget.onInteractionEnd,
                      clipBehavior: Clip.none,
                      child: imageCanvas,
                    ),
                  ),
                  selectionLayer,
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _startDrag(DragStartDetails details, Rect imageRect, Rect cropRect) {
    final Offset point = details.localPosition;
    if (!imageRect
        .inflate(widget.overlayStyle.handleHitSize / 2)
        .contains(point)) {
      return;
    }
    final _DragHandle? handle = _hitTestHandle(point, cropRect);
    if (handle == null) return;
    _dragHandle = handle;
    _dragStartPoint = point;
    _dragStartRect = cropRect;
    _dragImageRect = imageRect;
  }

  _DragHandle? _hitTestHandle(Offset point, Rect cropRect) {
    final double hitSize = widget.overlayStyle.handleHitSize;
    if (widget.allowResize) {
      final List<(_DragHandle, Offset)> handles = <(_DragHandle, Offset)>[
        (_DragHandle.topLeft, cropRect.topLeft),
        (_DragHandle.top, cropRect.topCenter),
        (_DragHandle.topRight, cropRect.topRight),
        (_DragHandle.right, cropRect.centerRight),
        (_DragHandle.bottomRight, cropRect.bottomRight),
        (_DragHandle.bottom, cropRect.bottomCenter),
        (_DragHandle.bottomLeft, cropRect.bottomLeft),
        (_DragHandle.left, cropRect.centerLeft),
      ];
      for (final (_DragHandle handle, Offset center) in handles) {
        if (Rect.fromCenter(
          center: center,
          width: hitSize,
          height: hitSize,
        ).contains(point)) {
          return handle;
        }
      }
    }
    if (widget.allowMove && cropRect.contains(point)) return _DragHandle.move;
    if (widget.allowNewSelection) return _DragHandle.newSelection;
    return null;
  }

  void _updateDrag(DragUpdateDetails details) {
    final _DragHandle? handle = _dragHandle;
    final Offset? startPoint = _dragStartPoint;
    final Rect? startRect = _dragStartRect;
    final Rect? imageRect = _dragImageRect;
    if (handle == null ||
        startPoint == null ||
        startRect == null ||
        imageRect == null) {
      return;
    }
    final Offset point = Offset(
      details.localPosition.dx.clamp(imageRect.left, imageRect.right),
      details.localPosition.dy.clamp(imageRect.top, imageRect.bottom),
    );
    final Rect next = switch (handle) {
      _DragHandle.move => _moveRect(startRect, point - startPoint, imageRect),
      _DragHandle.newSelection => _newSelection(startPoint, point, imageRect),
      _ => _resizeRect(handle, startRect, point, imageRect),
    };
    _controller.setRegion(_regionForRect(imageRect, next));
  }

  void _endDrag() {
    _dragHandle = null;
    _dragStartPoint = null;
    _dragStartRect = null;
    _dragImageRect = null;
  }

  void _resetEditor() {
    _controller.reset();
    _transformationController.value = Matrix4.identity();
  }

  Rect _newSelection(Offset start, Offset point, Rect bounds) {
    final _DragHandle corner = switch ((
      point.dx >= start.dx,
      point.dy >= start.dy,
    )) {
      (true, true) => _DragHandle.bottomRight,
      (true, false) => _DragHandle.topRight,
      (false, true) => _DragHandle.bottomLeft,
      (false, false) => _DragHandle.topLeft,
    };
    return _cornerRect(corner, anchor: start, pointer: point, bounds: bounds);
  }

  Rect _resizeRect(_DragHandle handle, Rect rect, Offset point, Rect bounds) {
    final double? ratio = widget.aspectRatio;
    if (ratio != null) {
      return _resizeAspectRect(handle, rect, point, bounds, ratio);
    }
    final double minimum = math.min(
      widget.minCropSize,
      math.min(bounds.width, bounds.height),
    );
    return switch (handle) {
      _DragHandle.left => Rect.fromLTRB(
        point.dx.clamp(bounds.left, rect.right - minimum),
        rect.top,
        rect.right,
        rect.bottom,
      ),
      _DragHandle.topLeft => Rect.fromLTRB(
        point.dx.clamp(bounds.left, rect.right - minimum),
        point.dy.clamp(bounds.top, rect.bottom - minimum),
        rect.right,
        rect.bottom,
      ),
      _DragHandle.top => Rect.fromLTRB(
        rect.left,
        point.dy.clamp(bounds.top, rect.bottom - minimum),
        rect.right,
        rect.bottom,
      ),
      _DragHandle.topRight => Rect.fromLTRB(
        rect.left,
        point.dy.clamp(bounds.top, rect.bottom - minimum),
        point.dx.clamp(rect.left + minimum, bounds.right),
        rect.bottom,
      ),
      _DragHandle.right => Rect.fromLTRB(
        rect.left,
        rect.top,
        point.dx.clamp(rect.left + minimum, bounds.right),
        rect.bottom,
      ),
      _DragHandle.bottomRight => Rect.fromLTRB(
        rect.left,
        rect.top,
        point.dx.clamp(rect.left + minimum, bounds.right),
        point.dy.clamp(rect.top + minimum, bounds.bottom),
      ),
      _DragHandle.bottom => Rect.fromLTRB(
        rect.left,
        rect.top,
        rect.right,
        point.dy.clamp(rect.top + minimum, bounds.bottom),
      ),
      _DragHandle.bottomLeft => Rect.fromLTRB(
        point.dx.clamp(bounds.left, rect.right - minimum),
        rect.top,
        rect.right,
        point.dy.clamp(rect.top + minimum, bounds.bottom),
      ),
      _ => rect,
    };
  }

  Rect _resizeAspectRect(
    _DragHandle handle,
    Rect rect,
    Offset point,
    Rect bounds,
    double ratio,
  ) {
    switch (handle) {
      case _DragHandle.topLeft:
        return _cornerRect(
          handle,
          anchor: rect.bottomRight,
          pointer: point,
          bounds: bounds,
        );
      case _DragHandle.topRight:
        return _cornerRect(
          handle,
          anchor: rect.bottomLeft,
          pointer: point,
          bounds: bounds,
        );
      case _DragHandle.bottomRight:
        return _cornerRect(
          handle,
          anchor: rect.topLeft,
          pointer: point,
          bounds: bounds,
        );
      case _DragHandle.bottomLeft:
        return _cornerRect(
          handle,
          anchor: rect.topRight,
          pointer: point,
          bounds: bounds,
        );
      case _DragHandle.left:
      case _DragHandle.right:
        final bool growsRight = handle == _DragHandle.right;
        final double anchorX = growsRight ? rect.left : rect.right;
        final double maximumWidth = math.min(
          growsRight ? bounds.right - anchorX : anchorX - bounds.left,
          2 *
              math.min(
                rect.center.dy - bounds.top,
                bounds.bottom - rect.center.dy,
              ) *
              ratio,
        );
        final double width = _clampAspectWidth(
          (point.dx - anchorX).abs(),
          maximumWidth,
          ratio,
        );
        final double height = width / ratio;
        return Rect.fromCenter(
          center: Offset(
            growsRight ? anchorX + width / 2 : anchorX - width / 2,
            rect.center.dy,
          ),
          width: width,
          height: height,
        );
      case _DragHandle.top:
      case _DragHandle.bottom:
        final bool growsDown = handle == _DragHandle.bottom;
        final double anchorY = growsDown ? rect.top : rect.bottom;
        final double maximumHeight = math.min(
          growsDown ? bounds.bottom - anchorY : anchorY - bounds.top,
          2 *
              math.min(
                rect.center.dx - bounds.left,
                bounds.right - rect.center.dx,
              ) /
              ratio,
        );
        final double minimumHeight = widget.minCropSize
            .clamp(0, maximumHeight)
            .toDouble();
        final double height = (point.dy - anchorY).abs().clamp(
          minimumHeight,
          maximumHeight,
        );
        final double width = height * ratio;
        return Rect.fromCenter(
          center: Offset(
            rect.center.dx,
            growsDown ? anchorY + height / 2 : anchorY - height / 2,
          ),
          width: width,
          height: height,
        );
      case _DragHandle.move:
      case _DragHandle.newSelection:
        return rect;
    }
  }

  Rect _cornerRect(
    _DragHandle corner, {
    required Offset anchor,
    required Offset pointer,
    required Rect bounds,
  }) {
    final double? ratio = widget.aspectRatio;
    final bool growsRight =
        corner == _DragHandle.topRight || corner == _DragHandle.bottomRight;
    final bool growsDown =
        corner == _DragHandle.bottomLeft || corner == _DragHandle.bottomRight;
    final double maximumWidth = growsRight
        ? bounds.right - anchor.dx
        : anchor.dx - bounds.left;
    final double maximumHeight = growsDown
        ? bounds.bottom - anchor.dy
        : anchor.dy - bounds.top;

    double width;
    double height;
    if (ratio == null) {
      final double minimum = math.min(
        widget.minCropSize,
        math.min(maximumWidth, maximumHeight),
      );
      width = (pointer.dx - anchor.dx).abs().clamp(minimum, maximumWidth);
      height = (pointer.dy - anchor.dy).abs().clamp(minimum, maximumHeight);
    } else {
      final double maxWidth = math.min(maximumWidth, maximumHeight * ratio);
      final double requestedWidth = math.min(
        (pointer.dx - anchor.dx).abs(),
        (pointer.dy - anchor.dy).abs() * ratio,
      );
      width = _clampAspectWidth(requestedWidth, maxWidth, ratio);
      height = width / ratio;
    }
    return Rect.fromLTRB(
      growsRight ? anchor.dx : anchor.dx - width,
      growsDown ? anchor.dy : anchor.dy - height,
      growsRight ? anchor.dx + width : anchor.dx,
      growsDown ? anchor.dy + height : anchor.dy,
    );
  }

  double _clampAspectWidth(
    double requested,
    double maximumWidth,
    double ratio,
  ) {
    final double minimumWidth = math
        .max(widget.minCropSize, widget.minCropSize * ratio)
        .clamp(0, maximumWidth)
        .toDouble();
    return requested.clamp(minimumWidth, maximumWidth).toDouble();
  }

  static Rect _moveRect(Rect rect, Offset delta, Rect bounds) {
    final double dx = delta.dx.clamp(
      bounds.left - rect.left,
      bounds.right - rect.right,
    );
    final double dy = delta.dy.clamp(
      bounds.top - rect.top,
      bounds.bottom - rect.bottom,
    );
    return rect.shift(Offset(dx, dy));
  }

  static Rect _transformRect(
    Rect rect,
    Matrix4 transform,
    Alignment? alignment,
    Size viewport,
  ) {
    final Offset origin = alignment?.alongSize(viewport) ?? Offset.zero;
    Offset apply(Offset point) =>
        origin + MatrixUtils.transformPoint(transform, point - origin);
    final Offset topLeft = apply(rect.topLeft);
    final Offset bottomRight = apply(rect.bottomRight);
    return Rect.fromLTRB(
      math.min(topLeft.dx, bottomRight.dx),
      math.min(topLeft.dy, bottomRight.dy),
      math.max(topLeft.dx, bottomRight.dx),
      math.max(topLeft.dy, bottomRight.dy),
    );
  }

  static Rect _containRect(Size viewport, Size image) {
    final double scale = math.min(
      viewport.width / image.width,
      viewport.height / image.height,
    );
    final Size fitted = image * scale;
    return Alignment.center.inscribe(fitted, Offset.zero & viewport);
  }

  static Rect _rectForRegion(Rect image, NormalizedCropRegion region) =>
      Rect.fromLTWH(
        image.left + region.left * image.width,
        image.top + region.top * image.height,
        region.width * image.width,
        region.height * image.height,
      );

  static NormalizedCropRegion _regionForRect(Rect image, Rect rect) {
    final double left = ((rect.left - image.left) / image.width)
        .clamp(0, 1)
        .toDouble();
    final double top = ((rect.top - image.top) / image.height)
        .clamp(0, 1)
        .toDouble();
    final double right = ((rect.right - image.left) / image.width)
        .clamp(0, 1)
        .toDouble();
    final double bottom = ((rect.bottom - image.top) / image.height)
        .clamp(0, 1)
        .toDouble();
    return NormalizedCropRegion(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
  }

  static bool _isFullRegion(NormalizedCropRegion region) =>
      region.left == 0 &&
      region.top == 0 &&
      region.width == 1 &&
      region.height == 1;
}

enum _DragHandle {
  move,
  newSelection,
  left,
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
}

final class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter(this.details);

  final CropEditorOverlayDetails details;

  @override
  void paint(Canvas canvas, Size size) {
    final CropOverlayStyle style = details.style;
    final RRect crop = RRect.fromRectAndRadius(
      details.cropRect,
      Radius.circular(style.borderRadius),
    );
    final Path mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(crop);
    canvas.drawPath(mask, Paint()..color = style.maskColor);

    if (style.showGrid && style.gridColumns > 1 && style.gridRows > 1) {
      canvas.save();
      canvas.clipRRect(crop);
      final Paint gridPaint = Paint()
        ..color = style.gridColor
        ..strokeWidth = style.gridStrokeWidth
        ..style = PaintingStyle.stroke;
      for (int column = 1; column < style.gridColumns; column++) {
        final double x =
            details.cropRect.left +
            details.cropRect.width * column / style.gridColumns;
        canvas.drawLine(
          Offset(x, details.cropRect.top),
          Offset(x, details.cropRect.bottom),
          gridPaint,
        );
      }
      for (int row = 1; row < style.gridRows; row++) {
        final double y =
            details.cropRect.top +
            details.cropRect.height * row / style.gridRows;
        canvas.drawLine(
          Offset(details.cropRect.left, y),
          Offset(details.cropRect.right, y),
          gridPaint,
        );
      }
      canvas.restore();
    }

    canvas.drawRRect(
      crop,
      Paint()
        ..color = style.borderColor
        ..strokeWidth = style.borderWidth
        ..style = PaintingStyle.stroke,
    );

    final Paint handlePaint = Paint()..color = style.handleColor;
    for (final Offset center in <Offset>[
      details.cropRect.topLeft,
      details.cropRect.topCenter,
      details.cropRect.topRight,
      details.cropRect.centerRight,
      details.cropRect.bottomRight,
      details.cropRect.bottomCenter,
      details.cropRect.bottomLeft,
      details.cropRect.centerLeft,
    ]) {
      if (style.handleShape == CropHandleShape.circle) {
        canvas.drawCircle(center, style.handleSize / 2, handlePaint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: center,
            width: style.handleSize,
            height: style.handleSize,
          ),
          handlePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) =>
      oldDelegate.details.cropRect != details.cropRect ||
      oldDelegate.details.imageRect != details.imageRect ||
      oldDelegate.details.style != details.style;
}

final class _DefaultCropEditorError extends StatelessWidget {
  const _DefaultCropEditorError({required this.error, required this.retry});

  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
