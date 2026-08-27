import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_media/dartitect_media.dart';
import 'package:dartitect_privacy/dartitect_privacy.dart';
import 'package:flutter/material.dart';

final class NativeCapabilityHarness extends StatefulWidget {
  const NativeCapabilityHarness({super.key, this.media, this.privacy});

  final GalleryMediaService? media;
  final TrackingAuthorizationService? privacy;

  @override
  State<NativeCapabilityHarness> createState() =>
      _NativeCapabilityHarnessState();
}

final class _NativeCapabilityHarnessState extends State<NativeCapabilityHarness>
    with WidgetsBindingObserver {
  late final GalleryMediaService _media =
      widget.media ?? MethodChannelGalleryMediaService();
  late final TrackingAuthorizationService _privacy =
      widget.privacy ?? MethodChannelTrackingAuthorizationService();
  final List<String> _log = <String>[];
  Directory? _temporary;
  bool _busy = false;
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final temporary = _temporary;
    if (temporary != null && temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _lifecycle = state;
      _append('lifecycle:${state.name}');
    });
  }

  Future<void> _run(String action, Future<String> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final outcome = await operation();
      if (!mounted) return;
      setState(() => _append('$action:$outcome'));
    } on Object {
      if (!mounted) return;
      setState(() => _append('$action:unexpected-failure'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _append(String message) {
    _log.add(message);
    if (_log.length > 40) _log.removeAt(0);
  }

  Future<File> _identifiedImage() async {
    final temporary = _temporary ??= await Directory.systemTemp.createTemp(
      'dartitect-qa-',
    );
    final image = File('${temporary.path}/dartitect-v1s13.png');
    if (!image.existsSync()) {
      await image.writeAsBytes(base64Decode(_onePixelPng), flush: true);
    }
    return image;
  }

  Future<String> _saveImage() async {
    final image = await _identifiedImage();
    final result = await _media.saveImage(
      GallerySaveRequest(path: image.path, album: 'Dartitect V1S13'),
    );
    return result.fold(
      (_) => image.existsSync() ? 'passed-source-preserved' : 'source-removed',
      (failure, _) => 'failed-${_failureCode(failure)}',
    );
  }

  Future<String> _missingFile() async {
    final image = await _identifiedImage();
    final result = await _media.saveImage(
      GallerySaveRequest(path: '${image.parent.path}/missing.png'),
    );
    return result.fold(
      (_) => 'unexpected-success',
      (failure, _) => failure is GalleryFileNotFoundFailure
          ? 'passed'
          : 'failed-${_failureCode(failure)}',
    );
  }

  Future<String> _invalidFile() async {
    final image = await _identifiedImage();
    final result = await _media.saveImage(
      GallerySaveRequest(path: image.parent.path),
    );
    return result.fold(
      (_) => 'unexpected-success',
      (failure, _) => failure is GalleryInvalidFileFailure
          ? 'passed'
          : 'failed-${_failureCode(failure)}',
    );
  }

  Future<String> _cleanup() async {
    await _media.clearOwnedState();
    await _media.clearOwnedState();
    final temporary = _temporary;
    if (temporary != null && temporary.existsSync()) {
      await temporary.delete(recursive: true);
    }
    _temporary = null;
    return 'passed-idempotent';
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Dartitect native QA')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Lifecycle: ${_lifecycle?.name ?? 'unknown'}',
            key: const Key('lifecycleStatus'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _button(
                key: 'privacyStatus',
                label: 'Privacy status',
                action: () => _run(
                  'privacy-status',
                  () async => (await _privacy.status()).name,
                ),
              ),
              _button(
                key: 'privacyRequest',
                label: 'Privacy request',
                action: () => _run(
                  'privacy-request',
                  () async => (await _privacy.request()).name,
                ),
              ),
              _button(
                key: 'mediaStatus',
                label: 'Media status',
                action: () => _run(
                  'media-status',
                  () async => (await _media.status()).name,
                ),
              ),
              _button(
                key: 'mediaRequest',
                label: 'Media request',
                action: () => _run(
                  'media-request',
                  () async => (await _media.requestAccess()).name,
                ),
              ),
              _button(
                key: 'saveImage',
                label: 'Save identified image',
                action: () => _run('save-image', _saveImage),
              ),
              _button(
                key: 'missingFile',
                label: 'Missing file',
                action: () => _run('missing-file', _missingFile),
              ),
              _button(
                key: 'invalidFile',
                label: 'Invalid file',
                action: () => _run('invalid-file', _invalidFile),
              ),
              _button(
                key: 'cleanup',
                label: 'Clean owned state',
                action: () => _run('cleanup', _cleanup),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Redacted QA log'),
          SelectableText(_log.join('\n'), key: const Key('qaLog')),
        ],
      ),
    ),
  );

  Widget _button({
    required String key,
    required String label,
    required VoidCallback action,
  }) => FilledButton(
    key: Key(key),
    onPressed: _busy ? null : action,
    child: Text(label),
  );
}

String _failureCode(GalleryFailure failure) => switch (failure) {
  GalleryFileNotFoundFailure() => 'file-not-found',
  GalleryInvalidFileFailure() => 'invalid-file',
  GalleryPermissionFailure() => 'permission',
  GalleryLimitedAccessFailure() => 'limited',
  GalleryCancelledFailure() => 'cancelled',
  GalleryNativeFailure(:final code) => 'native-$code',
};

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '/x8AAusB9Wl2nNwAAAAASUVORK5CYII=';
