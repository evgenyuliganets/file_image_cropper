import 'dart:io';

import 'package:file_image_cropper/file_image_cropper.dart';
import 'package:flutter/material.dart' hide ImageInfo;

void main() => runApp(const FileImageCropperExample());

class FileImageCropperExample extends StatelessWidget {
  const FileImageCropperExample({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: CropDemoPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CropDemoPage extends StatefulWidget {
  const CropDemoPage({super.key});

  @override
  State<CropDemoPage> createState() => _CropDemoPageState();
}

class _CropDemoPageState extends State<CropDemoPage> {
  final TextEditingController _pathController = TextEditingController();
  CropResult? _result;
  bool _busy = false;
  String _status = 'Enter a JPEG, PNG, or static WebP file path.';

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _cropFile() async {
    final String path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _status = 'Choose an input file first.');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Processing...';
    });

    try {
      final File input = File(path);
      final CropResult? nextResult = await showFileImageCropper(
        context,
        FileImageCropperPage(
          input: input,
          config: const CropperPageConfig(
            outputSize: PixelSize(width: 1024, height: 1024),
            outputFormat: OutputFormat.webp,
            webpOptions: WebpOptions(quality: 84),
          ),
          title: const Text('Choose crop area'),
          confirmLabel: 'Create WebP',
          overlayStyle: const CropOverlayStyle(
            borderColor: Colors.lightBlueAccent,
            handleColor: Colors.lightBlueAccent,
            handleShape: CropHandleShape.circle,
          ),
        ),
      );
      if (nextResult == null) {
        if (mounted) setState(() => _status = 'Crop cancelled.');
        return;
      }
      if (!mounted) {
        await nextResult.delete();
        return;
      }
      final CropResult? previous = _result;
      setState(() {
        _result = nextResult;
        _status = 'Created ${nextResult.file.path}';
      });
      await previous?.delete();
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteResult() async {
    final CropResult? result = _result;
    if (result == null) return;
    final bool deleted = await result.delete();
    if (!mounted) return;
    setState(() {
      _result = null;
      _status = deleted ? 'Managed result deleted.' : 'Nothing was deleted.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('file_image_cropper')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _pathController,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Input file path',
                  ),
                  onSubmitted: (_) => _cropFile(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _cropFile,
                  child: Text(_busy ? 'Processing...' : 'Crop and convert'),
                ),
                if (_result != null) ...<Widget>[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : _deleteResult,
                    child: const Text('Delete managed result'),
                  ),
                ],
                const SizedBox(height: 20),
                SelectableText(_status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
