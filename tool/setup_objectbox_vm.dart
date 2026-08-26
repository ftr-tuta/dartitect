import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _objectBoxVersion = '5.3.2';

/// Downloads an immutable ObjectBox release artifact into [destination].
typedef ObjectBoxDownloader = Future<void> Function(
  Uri source,
  File destination,
);

/// Extracts exactly [member] from [archive] into [destination].
typedef ObjectBoxArchiveExtractor = Future<void> Function(
  File archive,
  String member,
  File destination,
);

/// Replaces [destination] with [source] using a same-directory staging file.
typedef ObjectBoxAtomicInstaller = Future<void> Function(
  File source,
  File destination,
);

/// Selects the only approved artifact for an operating system and architecture.
typedef ObjectBoxArtifactSelector = ObjectBoxArtifact Function(
  String operatingSystem,
  String architecture,
);

/// An immutable, reviewed ObjectBox native release artifact.
final class ObjectBoxArtifact {
  /// Creates metadata for one approved host artifact.
  const ObjectBoxArtifact({
    required this.platform,
    required this.archiveName,
    required this.archiveSha256,
    required this.libraryName,
  });

  /// Stable platform identifier written to the cache marker.
  final String platform;

  /// Exact file name published by ObjectBox.
  final String archiveName;

  /// Expected SHA-256 of the complete downloaded archive.
  final String archiveSha256;

  /// Exact native library file name required by the fixture.
  final String libraryName;

  /// Exact archive member that may be extracted.
  String get archiveMember => 'lib/$libraryName';

  /// Fixed upstream release URL. Callers cannot supply a URL or version.
  Uri get downloadUri => Uri.https(
    'github.com',
    '/objectbox/objectbox-c/releases/download/v$_objectBoxVersion/$archiveName',
  );
}

/// Failure raised by the bounded ObjectBox setup operation.
final class ObjectBoxSetupException implements Exception {
  /// Creates a setup failure with a safe diagnostic.
  const ObjectBoxSetupException(this.message);

  /// Human-readable failure detail.
  final String message;

  @override
  String toString() => 'ObjectBox setup failed: $message';
}

/// Result of installing or revalidating the native fixture library.
final class ObjectBoxSetupResult {
  /// Creates an immutable setup result.
  const ObjectBoxSetupResult({
    required this.library,
    required this.platform,
    required this.reusedCache,
  });

  /// Installed native library.
  final File library;

  /// Selected approved platform.
  final String platform;

  /// Whether an already-installed library passed marker and hash validation.
  final bool reusedCache;
}

/// Selects one of the four approved ObjectBox 5.3.2 host artifacts.
ObjectBoxArtifact selectObjectBoxArtifact(
  String operatingSystem,
  String architecture,
) {
  final key = '${operatingSystem.toLowerCase()}:${architecture.toLowerCase()}';
  return switch (key) {
    'linux:x64' || 'linux:x86_64' || 'linux:amd64' => const ObjectBoxArtifact(
      platform: 'linux-x64',
      archiveName: 'objectbox-linux-x64.tar.gz',
      archiveSha256:
          '6dbb5450c36dd11ee9074f16ecc61e79b45ff43c2082934601f3166b39c8a613',
      libraryName: 'libobjectbox.so',
    ),
    'linux:arm64' || 'linux:aarch64' => const ObjectBoxArtifact(
      platform: 'linux-arm64',
      archiveName: 'objectbox-linux-aarch64.tar.gz',
      archiveSha256:
          'bdfbfbf4971057e11018ca6645697d8a40ebc7df56ccde63397cbb0e0609c0e8',
      libraryName: 'libobjectbox.so',
    ),
    'windows:x64' ||
    'windows:x86_64' ||
    'windows:amd64' => const ObjectBoxArtifact(
      platform: 'windows-x64',
      archiveName: 'objectbox-windows-x64.zip',
      archiveSha256:
          '57d7db013bbb46efe415307c9f3baf7564bdc40818ee1f1c42046f4241403d63',
      libraryName: 'objectbox.dll',
    ),
    'macos:x64' ||
    'macos:x86_64' ||
    'macos:arm64' ||
    'macos:aarch64' => const ObjectBoxArtifact(
      platform: 'macos-universal',
      archiveName: 'objectbox-macos-universal.zip',
      archiveSha256:
          '680c598573ede04b9762565d48d4e161ad286f786f159abb8da89353bfa1d0bc',
      libraryName: 'libobjectbox.dylib',
    ),
    _ => throw ObjectBoxSetupException(
      'unsupported host $operatingSystem/$architecture',
    ),
  };
}

/// Installs the approved ObjectBox library into the generated-model fixture.
final class ObjectBoxVmInstaller {
  /// Creates a setup operation rooted at [repositoryRoot].
  ObjectBoxVmInstaller({
    required this.repositoryRoot,
    String? operatingSystem,
    String? architecture,
    ObjectBoxDownloader? downloader,
    ObjectBoxArchiveExtractor? extractor,
    ObjectBoxAtomicInstaller? atomicInstaller,
    ObjectBoxArtifactSelector? artifactSelector,
    Directory? temporaryRoot,
    void Function(String message)? log,
  }) : operatingSystem = operatingSystem ?? Platform.operatingSystem,
       architecture = architecture ?? _currentArchitecture(),
       downloader = downloader ?? _download,
       extractor = extractor ?? _extractExactMember,
       atomicInstaller = atomicInstaller ?? _replaceAtomically,
       artifactSelector = artifactSelector ?? selectObjectBoxArtifact,
       temporaryRoot = temporaryRoot ?? Directory.systemTemp,
       log = log ?? stdout.writeln;

  /// Repository containing `tool/objectbox_native_fixture`.
  final Directory repositoryRoot;

  /// Normalized host operating system.
  final String operatingSystem;

  /// Normalized host architecture.
  final String architecture;

  /// Download boundary, injectable for deterministic offline tests.
  final ObjectBoxDownloader downloader;

  /// Archive boundary, injectable for deterministic offline tests.
  final ObjectBoxArchiveExtractor extractor;

  /// Final filesystem replacement boundary.
  final ObjectBoxAtomicInstaller atomicInstaller;

  /// Approved artifact selection boundary.
  final ObjectBoxArtifactSelector artifactSelector;

  /// Parent for per-run temporary directories.
  final Directory temporaryRoot;

  /// Progress destination.
  final void Function(String message) log;

  /// Revalidates a cache or downloads, verifies, and installs the library.
  Future<ObjectBoxSetupResult> install() async {
    final artifact = artifactSelector(operatingSystem, architecture);
    final fixtureLib = Directory(
      '${repositoryRoot.path}${Platform.pathSeparator}tool'
      '${Platform.pathSeparator}objectbox_native_fixture'
      '${Platform.pathSeparator}lib',
    );
    final target = File(
      '${fixtureLib.path}${Platform.pathSeparator}${artifact.libraryName}',
    );
    final marker = File(
      '${fixtureLib.path}${Platform.pathSeparator}.objectbox-vm.json',
    );
    if (await _isValidCache(target, marker, artifact)) {
      log('Reused verified ObjectBox $_objectBoxVersion: ${target.path}');
      return ObjectBoxSetupResult(
        library: target,
        platform: artifact.platform,
        reusedCache: true,
      );
    }

    Directory? scratch;
    try {
      await temporaryRoot.create(recursive: true);
      scratch = await temporaryRoot.createTemp('dartitect-objectbox-');
      final archive = File(
        '${scratch.path}${Platform.pathSeparator}${artifact.archiveName}',
      );
      await downloader(artifact.downloadUri, archive);
      if (!await archive.exists()) {
        throw const ObjectBoxSetupException(
          'the downloader did not create an archive',
        );
      }
      final actualArchiveHash = await _sha256File(archive);
      if (actualArchiveHash != artifact.archiveSha256) {
        throw ObjectBoxSetupException(
          'SHA-256 mismatch for ${artifact.archiveName}: '
          'expected ${artifact.archiveSha256}, got $actualArchiveHash',
        );
      }

      final extracted = File(
        '${scratch.path}${Platform.pathSeparator}${artifact.libraryName}',
      );
      await extractor(archive, artifact.archiveMember, extracted);
      if (!await extracted.exists() || await extracted.length() == 0) {
        throw ObjectBoxSetupException(
          'archive member ${artifact.archiveMember} is missing or empty',
        );
      }
      final installedHash = await _sha256File(extracted);

      await fixtureLib.create(recursive: true);
      await atomicInstaller(extracted, target);
      final markerSource = File(
        '${scratch.path}${Platform.pathSeparator}.objectbox-vm.json',
      );
      final markerData = <String, Object?>{
        'schemaVersion': 1,
        'objectBoxVersion': _objectBoxVersion,
        'platform': artifact.platform,
        'archive': artifact.archiveName,
        'archiveSha256': artifact.archiveSha256,
        'library': artifact.libraryName,
        'librarySha256': installedHash,
      };
      await markerSource.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(markerData)}\n',
        flush: true,
      );
      await atomicInstaller(markerSource, marker);
      log('Installed ObjectBox $_objectBoxVersion: ${target.path}');
      return ObjectBoxSetupResult(
        library: target,
        platform: artifact.platform,
        reusedCache: false,
      );
    } on ObjectBoxSetupException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ObjectBoxSetupException('filesystem operation failed: $error');
    } on ProcessException catch (error) {
      throw ObjectBoxSetupException('archive extraction failed: $error');
    } on IOException catch (error) {
      throw ObjectBoxSetupException('I/O operation failed: $error');
    } on FormatException catch (error) {
      throw ObjectBoxSetupException('archive is invalid or truncated: $error');
    } finally {
      if (scratch != null && await scratch.exists()) {
        await scratch.delete(recursive: true);
      }
    }
  }
}

Future<bool> _isValidCache(
  File target,
  File marker,
  ObjectBoxArtifact artifact,
) async {
  if (!await target.exists() || !await marker.exists()) return false;
  try {
    final decoded = jsonDecode(await marker.readAsString());
    if (decoded is! Map<String, Object?> ||
        decoded['schemaVersion'] != 1 ||
        decoded['objectBoxVersion'] != _objectBoxVersion ||
        decoded['platform'] != artifact.platform ||
        decoded['archive'] != artifact.archiveName ||
        decoded['archiveSha256'] != artifact.archiveSha256 ||
        decoded['library'] != artifact.libraryName) {
      return false;
    }
    final expectedLibraryHash = decoded['librarySha256'];
    return expectedLibraryHash is String &&
        expectedLibraryHash == await _sha256File(target);
  } on FileSystemException {
    return false;
  } on FormatException {
    return false;
  }
}

Future<String> _sha256File(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> _download(Uri source, File destination) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(source);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw ObjectBoxSetupException(
        'download returned HTTP ${response.statusCode}',
      );
    }
    final sink = destination.openWrite();
    try {
      await response.pipe(sink);
    } finally {
      await sink.close();
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _extractExactMember(
  File archive,
  String member,
  File destination,
) async {
  final result = await Process.run('tar', <String>[
    '-xOf',
    archive.path,
    member,
  ], stdoutEncoding: null);
  if (result.exitCode != 0) {
    final diagnostic = (result.stderr as String).trim();
    throw ObjectBoxSetupException(
      'archive does not contain exact member $member'
      '${diagnostic.isEmpty ? '' : ': $diagnostic'}',
    );
  }
  final bytes = result.stdout as List<int>;
  if (bytes.isEmpty) {
    throw ObjectBoxSetupException('archive member $member is empty');
  }
  await destination.writeAsBytes(bytes, flush: true);
}

Future<void> _replaceAtomically(File source, File destination) async {
  final suffix = '${pid}-${DateTime.now().microsecondsSinceEpoch}';
  final staged = File('${destination.path}.$suffix.tmp');
  final backup = File('${destination.path}.$suffix.backup');
  await source.copy(staged.path);
  try {
    try {
      await staged.rename(destination.path);
      return;
    } on FileSystemException {
      if (!await destination.exists()) rethrow;
    }

    await destination.rename(backup.path);
    try {
      await staged.rename(destination.path);
      await backup.delete();
    } on Object {
      if (await backup.exists() && !await destination.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
  } finally {
    if (await staged.exists()) await staged.delete();
    if (await backup.exists()) await backup.delete();
  }
}

String _currentArchitecture() => switch (Abi.current()) {
  Abi.linuxX64 || Abi.windowsX64 || Abi.macosX64 => 'x64',
  Abi.linuxArm64 || Abi.macosArm64 => 'arm64',
  final abi => '$abi',
};

/// Runs the bounded command-line entrypoint.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/setup_objectbox_vm.dart');
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  try {
    await ObjectBoxVmInstaller(repositoryRoot: root).install();
  } on ObjectBoxSetupException catch (error) {
    stderr.writeln(error);
    exitCode = error.message.startsWith('unsupported host') ? 2 : 1;
  }
}
