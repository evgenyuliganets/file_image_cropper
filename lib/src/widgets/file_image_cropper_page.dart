import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ffi/native_image_engine.dart';
import '../models/crop_region.dart';
import '../models/crop_request.dart';
import '../models/crop_result.dart';
import '../models/image_info.dart' as cropper;
import '../models/jpeg_options.dart';
import '../models/output_format.dart';
import '../models/pixel_size.dart';
import '../models/resize_options.dart';
import '../models/webp_options.dart';
import 'crop_editor.dart';
import 'crop_editor_controller.dart';
import 'crop_overlay_style.dart';

typedef CropRequestBuilder =
    CropRequest Function(File input, NormalizedCropRegion region);
typedef CropExecutor = Future<CropResult> Function(CropRequest request);
typedef CropperAppBarBuilder =
    PreferredSizeWidget Function(
      BuildContext context,
      CropperPageActions actions,
    );
typedef CropperBodyBuilder =
    Widget Function(
      BuildContext context,
      Widget editor,
      Widget controls,
      CropperPageActions actions,
    );
typedef CropperControlsBuilder =
    Widget Function(
      BuildContext context,
      CropperPageActions actions,
      Widget defaultControls,
    );
typedef CropperActionButtonBuilder =
    Widget Function(
      BuildContext context,
      VoidCallback? onPressed,
      bool isProcessing,
    );
typedef CropperEditorBuilder =
    Widget Function(
      BuildContext context,
      CropperPageActions actions,
      double? aspectRatio,
    );
typedef CropperProcessingBuilder =
    Widget Function(BuildContext context, CropperPageActions actions);
typedef CropperPageErrorBuilder =
    Widget Function(BuildContext context, Object error);

/// Output and encoding options used by [FileImageCropperPage].
final class CropperPageConfig {
  const CropperPageConfig({
    this.output,
    this.overwrite = false,
    this.outputSize,
    this.resizeFilter = ResizeFilter.bilinear,
    this.aspectMismatchPolicy = AspectMismatchPolicy.adjustCrop,
    this.outputFormat = OutputFormat.png,
    this.jpegOptions = const JpegOptions(),
    this.webpOptions = const WebpOptions(),
  });

  final File? output;
  final bool overwrite;
  final PixelSize? outputSize;
  final ResizeFilter resizeFilter;
  final AspectMismatchPolicy aspectMismatchPolicy;
  final OutputFormat outputFormat;
  final JpegOptions jpegOptions;
  final WebpOptions webpOptions;

  CropRequest createRequest(File input, NormalizedCropRegion region) =>
      CropRequest(
        input: input,
        region: region,
        output: output,
        overwrite: overwrite,
        outputSize: outputSize,
        resizeFilter: resizeFilter,
        aspectMismatchPolicy: aspectMismatchPolicy,
        outputFormat: outputFormat,
        jpegOptions: jpegOptions,
        webpOptions: webpOptions,
      );
}

/// Current page state and callbacks supplied to customization builders.
final class CropperPageActions {
  const CropperPageActions({
    required this.controller,
    required this.isProcessing,
    required this.error,
    required this.confirm,
    required this.cancel,
    required this.reset,
    required this.transformationController,
    required this.interactionMode,
    required this.toggleInteractionMode,
  });

  final CropEditorController controller;
  final bool isProcessing;
  final Object? error;
  final VoidCallback? confirm;
  final VoidCallback? cancel;
  final VoidCallback reset;
  final TransformationController transformationController;
  final CropEditorInteractionMode interactionMode;
  final VoidCallback? toggleInteractionMode;
}

/// Ready-to-use crop screen. Every major visual section can be replaced.
class FileImageCropperPage extends StatefulWidget {
  const FileImageCropperPage({
    required this.input,
    this.config = const CropperPageConfig(),
    this.requestBuilder,
    this.executor = _defaultCropExecutor,
    this.controller,
    this.imageInfo,
    this.aspectRatio,
    this.enablePanAndZoom = true,
    this.initialInteractionMode = CropEditorInteractionMode.select,
    this.transformationController,
    this.minScale = 1,
    this.maxScale = 8,
    this.editorBuilder,
    this.appBar,
    this.appBarBuilder,
    this.bodyBuilder,
    this.controlsBuilder,
    this.confirmButtonBuilder,
    this.cancelButtonBuilder,
    this.processingBuilder,
    this.pageErrorBuilder,
    this.imageBuilder,
    this.overlayBuilder,
    this.loadingBuilder,
    this.editorErrorBuilder,
    this.overlayStyle = const CropOverlayStyle(),
    this.showDefaultOverlay = true,
    this.editorPadding = const EdgeInsets.all(16),
    this.editorBackgroundColor = Colors.black,
    this.scaffoldBackgroundColor,
    this.controlsPadding = const EdgeInsets.all(16),
    this.controlsBackgroundColor,
    this.title = const Text('Crop image'),
    this.confirmLabel = 'Crop',
    this.cancelLabel = 'Cancel',
    this.showDefaultAppBar = true,
    this.showResetAction = true,
    this.popOnComplete = true,
    this.popOnCancel = true,
    this.onCompleted,
    this.onCancelled,
    this.onError,
    super.key,
  }) : assert(aspectRatio == null || aspectRatio > 0),
       assert(minScale > 0),
       assert(maxScale >= minScale);

  final File input;
  final CropperPageConfig config;
  final CropRequestBuilder? requestBuilder;
  final CropExecutor executor;
  final CropEditorController? controller;
  final cropper.ImageInfo? imageInfo;
  final double? aspectRatio;
  final bool enablePanAndZoom;
  final CropEditorInteractionMode initialInteractionMode;
  final TransformationController? transformationController;
  final double minScale;
  final double maxScale;

  final CropperEditorBuilder? editorBuilder;
  final PreferredSizeWidget? appBar;
  final CropperAppBarBuilder? appBarBuilder;
  final CropperBodyBuilder? bodyBuilder;
  final CropperControlsBuilder? controlsBuilder;
  final CropperActionButtonBuilder? confirmButtonBuilder;
  final CropperActionButtonBuilder? cancelButtonBuilder;
  final CropperProcessingBuilder? processingBuilder;
  final CropperPageErrorBuilder? pageErrorBuilder;
  final CropEditorImageBuilder? imageBuilder;
  final CropEditorOverlayBuilder? overlayBuilder;
  final CropEditorLoadingBuilder? loadingBuilder;
  final CropEditorErrorBuilder? editorErrorBuilder;

  final CropOverlayStyle overlayStyle;
  final bool showDefaultOverlay;

  /// Minimum space around the editor image. Horizontal values are increased
  /// automatically when Android reserves a wider system-gesture area.
  final EdgeInsets editorPadding;
  final Color editorBackgroundColor;
  final Color? scaffoldBackgroundColor;
  final EdgeInsets controlsPadding;
  final Color? controlsBackgroundColor;
  final Widget title;
  final String confirmLabel;
  final String cancelLabel;
  final bool showDefaultAppBar;
  final bool showResetAction;
  final bool popOnComplete;
  final bool popOnCancel;
  final ValueChanged<CropResult>? onCompleted;
  final VoidCallback? onCancelled;
  final void Function(Object error, StackTrace stackTrace)? onError;

  @override
  State<FileImageCropperPage> createState() => _FileImageCropperPageState();
}

class _FileImageCropperPageState extends State<FileImageCropperPage> {
  late CropEditorController _controller;
  late bool _ownsController;
  late TransformationController _transformationController;
  late bool _ownsTransformationController;
  late CropEditorInteractionMode _interactionMode;
  bool _isProcessing = false;
  Object? _error;

  double? get _effectiveAspectRatio =>
      widget.aspectRatio ?? widget.config.outputSize?.aspectRatio;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
    _attachTransformationController(widget.transformationController);
    _interactionMode = widget.enablePanAndZoom
        ? widget.initialInteractionMode
        : CropEditorInteractionMode.select;
  }

  @override
  void didUpdateWidget(FileImageCropperPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController();
      _attachController(widget.controller);
    }
    if (oldWidget.transformationController != widget.transformationController) {
      _detachTransformationController();
      _attachTransformationController(widget.transformationController);
    }
    if (oldWidget.initialInteractionMode != widget.initialInteractionMode ||
        oldWidget.enablePanAndZoom != widget.enablePanAndZoom) {
      _interactionMode = widget.enablePanAndZoom
          ? widget.initialInteractionMode
          : CropEditorInteractionMode.select;
    }
  }

  @override
  void dispose() {
    _detachController();
    _detachTransformationController();
    super.dispose();
  }

  void _attachController(CropEditorController? supplied) {
    _ownsController = supplied == null;
    _controller = supplied ?? CropEditorController();
  }

  void _detachController() {
    if (_ownsController) _controller.dispose();
  }

  void _attachTransformationController(TransformationController? supplied) {
    _ownsTransformationController = supplied == null;
    _transformationController = supplied ?? TransformationController();
  }

  void _detachTransformationController() {
    if (_ownsTransformationController) _transformationController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets systemGestures = MediaQuery.systemGestureInsetsOf(context);
    final EdgeInsets effectiveEditorPadding = EdgeInsets.fromLTRB(
      math.max(widget.editorPadding.left, systemGestures.left),
      widget.editorPadding.top,
      math.max(widget.editorPadding.right, systemGestures.right),
      widget.editorPadding.bottom,
    );
    final CropperPageActions actions = CropperPageActions(
      controller: _controller,
      isProcessing: _isProcessing,
      error: _error,
      confirm: _isProcessing ? null : () => unawaited(_confirm()),
      cancel: _isProcessing ? null : _cancel,
      reset: _reset,
      transformationController: _transformationController,
      interactionMode: _interactionMode,
      toggleInteractionMode: widget.enablePanAndZoom && !_isProcessing
          ? _toggleInteractionMode
          : null,
    );
    final Widget editor =
        widget.editorBuilder?.call(context, actions, _effectiveAspectRatio) ??
        CropEditor(
          input: widget.input,
          imageInfo: widget.imageInfo,
          controller: _controller,
          aspectRatio: _effectiveAspectRatio,
          enabled: !_isProcessing,
          interactionMode: _interactionMode,
          transformationController: _transformationController,
          minScale: widget.minScale,
          maxScale: widget.maxScale,
          padding: effectiveEditorPadding,
          backgroundColor: widget.editorBackgroundColor,
          overlayStyle: widget.overlayStyle,
          showDefaultOverlay: widget.showDefaultOverlay,
          imageBuilder: widget.imageBuilder,
          overlayBuilder: widget.overlayBuilder,
          loadingBuilder: widget.loadingBuilder,
          errorBuilder: widget.editorErrorBuilder,
        );
    final Widget defaultControls = _DefaultCropperControls(
      actions: actions,
      confirmLabel: widget.confirmLabel,
      cancelLabel: widget.cancelLabel,
      padding: widget.controlsPadding,
      backgroundColor: widget.controlsBackgroundColor,
      confirmButtonBuilder: widget.confirmButtonBuilder,
      cancelButtonBuilder: widget.cancelButtonBuilder,
      pageErrorBuilder: widget.pageErrorBuilder,
    );
    final Widget controls =
        widget.controlsBuilder?.call(context, actions, defaultControls) ??
        defaultControls;
    final Widget body =
        widget.bodyBuilder?.call(context, editor, controls, actions) ??
        Column(
          children: <Widget>[
            Expanded(child: editor),
            controls,
          ],
        );
    final PreferredSizeWidget? effectiveAppBar =
        widget.appBarBuilder?.call(context, actions) ??
        widget.appBar ??
        (widget.showDefaultAppBar
            ? AppBar(
                title: widget.title,
                leading: IconButton(
                  onPressed: actions.cancel,
                  tooltip: widget.cancelLabel,
                  icon: const Icon(Icons.close),
                ),
                actions: <Widget>[
                  if (widget.enablePanAndZoom)
                    IconButton(
                      onPressed: actions.toggleInteractionMode,
                      tooltip:
                          _interactionMode == CropEditorInteractionMode.select
                          ? 'Pan and zoom'
                          : 'Edit selection',
                      icon: Icon(
                        _interactionMode == CropEditorInteractionMode.select
                            ? Icons.pan_tool_alt
                            : Icons.crop,
                      ),
                    ),
                  if (widget.showResetAction)
                    IconButton(
                      onPressed: _isProcessing ? null : actions.reset,
                      tooltip: 'Reset',
                      icon: const Icon(Icons.refresh),
                    ),
                ],
              )
            : null);

    return Scaffold(
      backgroundColor: widget.scaffoldBackgroundColor,
      appBar: effectiveAppBar,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          body,
          if (_isProcessing)
            widget.processingBuilder?.call(context, actions) ??
                const ColoredBox(
                  color: Color(0x55000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final CropRequest request =
          widget.requestBuilder?.call(widget.input, _controller.region) ??
          widget.config.createRequest(widget.input, _controller.region);
      final CropResult result = await widget.executor(request);
      if (!mounted) return;
      widget.onCompleted?.call(result);
      if (widget.popOnComplete) Navigator.of(context).pop(result);
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _error = error);
      widget.onError?.call(error, stackTrace);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _toggleInteractionMode() {
    setState(() {
      _interactionMode = _interactionMode == CropEditorInteractionMode.select
          ? CropEditorInteractionMode.panAndZoom
          : CropEditorInteractionMode.select;
    });
  }

  void _reset() {
    _controller.reset();
    _transformationController.value = Matrix4.identity();
  }

  void _cancel() {
    widget.onCancelled?.call();
    if (widget.popOnCancel) Navigator.of(context).maybePop<CropResult>();
  }
}

/// Pushes a fully configured crop page and returns its managed/explicit result.
Future<CropResult?> showFileImageCropper(
  BuildContext context,
  FileImageCropperPage page, {
  RouteSettings? routeSettings,
  bool fullscreenDialog = false,
}) => Navigator.of(context).push<CropResult>(
  MaterialPageRoute<CropResult>(
    builder: (_) => page,
    settings: routeSettings,
    fullscreenDialog: fullscreenDialog,
  ),
);

Future<CropResult> _defaultCropExecutor(CropRequest request) =>
    const NativeImageEngine().crop(request);

final class _DefaultCropperControls extends StatelessWidget {
  const _DefaultCropperControls({
    required this.actions,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.padding,
    required this.backgroundColor,
    required this.confirmButtonBuilder,
    required this.cancelButtonBuilder,
    required this.pageErrorBuilder,
  });

  final CropperPageActions actions;
  final String confirmLabel;
  final String cancelLabel;
  final EdgeInsets padding;
  final Color? backgroundColor;
  final CropperActionButtonBuilder? confirmButtonBuilder;
  final CropperActionButtonBuilder? cancelButtonBuilder;
  final CropperPageErrorBuilder? pageErrorBuilder;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: backgroundColor ?? Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      minimum: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (actions.error case final Object error) ...<Widget>[
            pageErrorBuilder?.call(context, error) ??
                Text(
                  error.toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            const SizedBox(height: 12),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child:
                    cancelButtonBuilder?.call(
                      context,
                      actions.cancel,
                      actions.isProcessing,
                    ) ??
                    OutlinedButton(
                      onPressed: actions.cancel,
                      child: Text(cancelLabel),
                    ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child:
                    confirmButtonBuilder?.call(
                      context,
                      actions.confirm,
                      actions.isProcessing,
                    ) ??
                    FilledButton(
                      onPressed: actions.confirm,
                      child: Text(confirmLabel),
                    ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
