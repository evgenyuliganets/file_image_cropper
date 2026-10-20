import 'dart:io';

import 'package:file_image_cropper/file_image_cropper.dart';
import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_test/flutter_test.dart';

const ImageInfo _imageInfo = ImageInfo(
  width: 400,
  height: 300,
  format: ImageFormat.png,
  orientation: 1,
);

void main() {
  testWidgets('selection can be moved and reports normalized coordinates', (
    WidgetTester tester,
  ) async {
    final CropEditorController controller = CropEditorController(
      initialRegion: const NormalizedCropRegion(
        left: 0.25,
        top: 0.25,
        width: 0.5,
        height: 0.5,
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: CropEditor(
              input: File('unused.png'),
              imageInfo: _imageInfo,
              controller: controller,
              imageBuilder: (_, _, _) => const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ),
    );

    final Finder editor = find.byType(CropEditor);
    final Offset center = tester.getCenter(editor);
    await tester.dragFrom(center, const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.region.left, closeTo(0.35, 1e-9));
    expect(controller.region.top, closeTo(0.25, 1e-9));
    expect(controller.region.width, closeTo(0.5, 1e-9));
    expect(controller.region.height, closeTo(0.5, 1e-9));
  });

  testWidgets('aspect ratio initializes the largest centered selection', (
    WidgetTester tester,
  ) async {
    final CropEditorController controller = CropEditorController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: CropEditor(
            input: File('unused.png'),
            imageInfo: const ImageInfo(
              width: 400,
              height: 200,
              format: ImageFormat.png,
              orientation: 1,
            ),
            controller: controller,
            aspectRatio: 1,
            imageBuilder: (_, _, _) => const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(controller.region.left, closeTo(0.25, 1e-9));
    expect(controller.region.top, closeTo(0, 1e-9));
    expect(controller.region.width, closeTo(0.5, 1e-9));
    expect(controller.region.height, closeTo(1, 1e-9));
  });

  testWidgets('corner handles resize the selected area', (
    WidgetTester tester,
  ) async {
    final CropEditorController controller = CropEditorController(
      initialRegion: const NormalizedCropRegion(
        left: 0.25,
        top: 0.25,
        width: 0.5,
        height: 0.5,
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: CropEditor(
              input: File('unused.png'),
              imageInfo: _imageInfo,
              controller: controller,
              imageBuilder: (_, _, _) => const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ),
    );

    final Offset editorTopLeft = tester.getTopLeft(find.byType(CropEditor));
    await tester.dragFrom(
      editorTopLeft + const Offset(100, 75),
      const Offset(-40, -30),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.region.left, closeTo(0.15, 1e-9));
    expect(controller.region.top, closeTo(0.15, 1e-9));
    expect(controller.region.width, closeTo(0.6, 1e-9));
    expect(controller.region.height, closeTo(0.6, 1e-9));
  });

  testWidgets('overlay tracks the transformed image in viewport coordinates', (
    WidgetTester tester,
  ) async {
    final CropEditorController controller = CropEditorController(
      initialRegion: const NormalizedCropRegion(
        left: 0.25,
        top: 0.25,
        width: 0.5,
        height: 0.5,
      ),
    );
    final TransformationController transformation = TransformationController();
    addTearDown(controller.dispose);
    addTearDown(transformation.dispose);
    CropEditorOverlayDetails? details;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: CropEditor(
              input: File('unused.png'),
              imageInfo: _imageInfo,
              controller: controller,
              transformationController: transformation,
              interactionMode: CropEditorInteractionMode.panAndZoom,
              imageBuilder: (_, _, _) => const ColoredBox(color: Colors.blue),
              overlayBuilder: (_, CropEditorOverlayDetails value) {
                details = value;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    expect(details!.imageRect.width, closeTo(400, 1e-9));
    expect(details!.cropRect.width, closeTo(200, 1e-9));

    transformation.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();

    expect(details!.imageRect.width, closeTo(800, 1e-9));
    expect(details!.cropRect.width, closeTo(400, 1e-9));
  });

  testWidgets('overlay paints across padding without changing crop bounds', (
    WidgetTester tester,
  ) async {
    CropEditorOverlayDetails? details;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: CropEditor(
              input: File('unused.png'),
              imageInfo: const ImageInfo(
                width: 360,
                height: 260,
                format: ImageFormat.png,
                orientation: 1,
              ),
              padding: const EdgeInsets.all(20),
              imageBuilder: (_, _, _) => const ColoredBox(color: Colors.blue),
              overlayBuilder: (_, CropEditorOverlayDetails value) {
                details = value;
                return const SizedBox.expand(key: Key('full-overlay'));
              },
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('full-overlay'))),
      const Size(400, 300),
    );
    expect(details!.imageRect, const Rect.fromLTWH(20, 20, 360, 260));
    expect(details!.cropRect, details!.imageRect);
  });

  testWidgets('page builders can replace every major visual section', (
    WidgetTester tester,
  ) async {
    CropRequest? capturedRequest;
    CropResult? completedResult;
    final CropResult expected = CropResult(
      file: File('custom-result.png'),
      isManaged: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FileImageCropperPage(
          input: File('unused.png'),
          imageInfo: _imageInfo,
          config: const CropperPageConfig(
            outputSize: PixelSize(width: 200, height: 150),
          ),
          popOnComplete: false,
          executor: (CropRequest request) async {
            capturedRequest = request;
            return expected;
          },
          onCompleted: (CropResult result) => completedResult = result,
          appBarBuilder: (_, _) => AppBar(
            key: const Key('custom-app-bar'),
            title: const Text('My cropper'),
          ),
          bodyBuilder: (_, Widget editor, Widget controls, _) => Column(
            key: const Key('custom-body'),
            children: <Widget>[
              Expanded(child: editor),
              controls,
            ],
          ),
          imageBuilder: (_, _, _) => const ColoredBox(color: Colors.blue),
          overlayBuilder: (_, _) => const SizedBox(key: Key('custom-overlay')),
          confirmButtonBuilder: (_, VoidCallback? onPressed, _) => FilledButton(
            key: const Key('custom-confirm'),
            onPressed: onPressed,
            child: const Text('Do it'),
          ),
          cancelButtonBuilder: (_, VoidCallback? onPressed, _) =>
              OutlinedButton(
                key: const Key('custom-cancel'),
                onPressed: onPressed,
                child: const Text('Nope'),
              ),
        ),
      ),
    );

    expect(find.byKey(const Key('custom-app-bar')), findsOneWidget);
    expect(find.byKey(const Key('custom-body')), findsOneWidget);
    expect(find.byKey(const Key('custom-overlay')), findsOneWidget);
    expect(find.byKey(const Key('custom-cancel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('custom-confirm')));
    await tester.pumpAndSettle();

    expect(capturedRequest, isNotNull);
    expect(capturedRequest!.outputSize?.width, 200);
    expect(capturedRequest!.outputSize?.height, 150);
    expect(capturedRequest!.effectiveRegion, isA<NormalizedCropRegion>());
    expect(completedResult, same(expected));
  });

  testWidgets('default page toggles between selection and precise pan/zoom', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FileImageCropperPage(
          input: File('unused.png'),
          imageInfo: _imageInfo,
          popOnComplete: false,
          popOnCancel: false,
          imageBuilder: (_, _, _) => const ColoredBox(color: Colors.blue),
        ),
      ),
    );

    InteractiveViewer viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.panEnabled, isFalse);
    expect(viewer.scaleEnabled, isFalse);

    await tester.tap(find.byTooltip('Pan and zoom'));
    await tester.pump();

    viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.panEnabled, isTrue);
    expect(viewer.scaleEnabled, isTrue);
    expect(find.byTooltip('Edit selection'), findsOneWidget);
  });

  testWidgets('default page avoids system gesture edges', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            systemGestureInsets: EdgeInsets.only(left: 24, right: 32),
          ),
          child: FileImageCropperPage(
            input: File('unused.png'),
            imageInfo: _imageInfo,
            imageBuilder: (_, _, _) => const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    );

    final CropEditor editor = tester.widget<CropEditor>(
      find.byType(CropEditor),
    );
    expect(editor.padding, const EdgeInsets.fromLTRB(24, 16, 32, 16));
    expect(editor.overlayStyle.handleHitSize, 48);
  });
}
