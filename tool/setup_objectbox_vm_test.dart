import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'setup_objectbox_vm.dart';

void main() {
  group('approved artifact selection', () {
    final cases = <(String, String, String, String)>[
      ('linux', 'x64', 'objectbox-linux-x64.tar.gz', 'lib/libobjectbox.so'),
      (
        'linux',
        'arm64',
        'objectbox-linux-aarch64.tar.gz',
        'lib/libobjectbox.so',
      ),
      ('windows', 'x64', 'objectbox-windows-x64.zip', 'lib/objectbox.dll'),
      (
        'macos',
        'arm64',
        'objectbox-macos-universal.zip',
        'lib/libobjectbox.dylib',
      ),
    ];

    for (final value in cases) {
      test('${value.$1}/${value.$2}', () {
        final artifact = selectObjectBoxArtifact(value.$1, value.$2);
        expect(artifact.archiveName, value.$3);
        expect(artifact.archiveMember, value.$4);
        expect(artifact.downloadUri.host, 'github.com');
        expect(
          artifact.downloadUri.path,
          contains('/objectbox-c/releases/download/v5.3.2/'),
        );
      });
    }

    test('rejects unsupported hosts', () {
      expect(
        () => selectObjectBoxArtifact('freebsd', 'x64'),
        throwsA(isA<ObjectBoxSetupException>()),
      );
      expect(
        () => selectObjectBoxArtifact('windows', 'arm64'),
        throwsA(isA<ObjectBoxSetupException>()),
      );
    });
  });

  test(
    'reuses only a cache whose installed library hash still matches',
    () async {
      final context = await _TestContext.create();
      addTearDown(context.dispose);
      var downloads = 0;
      final installer = context.installer(
        downloader: (source, destination) async {
          downloads += 1;
          await destination.writeAsBytes(context.archiveBytes);
        },
      );

      final first = await installer.install();
      final second = await installer.install();

      expect(first.reusedCache, isFalse);
      expect(second.reusedCache, isTrue);
      expect(downloads, 1);
      expect(await second.library.readAsBytes(), context.libraryBytes);
    },
  );

  test('redownloads when the installed cache library was modified', () async {
    final context = await _TestContext.create();
    addTearDown(context.dispose);
    var downloads = 0;
    final installer = context.installer(
      downloader: (source, destination) async {
        downloads += 1;
        await destination.writeAsBytes(context.archiveBytes);
      },
    );

    final first = await installer.install();
    await first.library.writeAsString('tampered cache');
    final repaired = await installer.install();

    expect(repaired.reusedCache, isFalse);
    expect(downloads, 2);
    expect(await repaired.library.readAsBytes(), context.libraryBytes);
  });

  test('rejects an archive with the wrong SHA-256', () async {
    final context = await _TestContext.create();
    addTearDown(context.dispose);
    final installer = context.installer(
      artifact: _artifactFor(const <int>[1, 2, 3]),
      downloader: (source, destination) =>
          destination.writeAsBytes(const <int>[3, 2, 1]),
    );

    await expectLater(
      installer.install(),
      throwsA(
        isA<ObjectBoxSetupException>().having(
          (error) => error.message,
          'message',
          contains('SHA-256 mismatch'),
        ),
      ),
    );
  });

  test('reports a correctly hashed but truncated archive', () async {
    final context = await _TestContext.create();
    addTearDown(context.dispose);
    const truncated = <int>[0x50, 0x4b, 0x03];
    final installer = context.installer(
      artifact: _artifactFor(truncated),
      downloader: (source, destination) => destination.writeAsBytes(truncated),
      extractor: (archive, member, destination) async {
        throw const FormatException('unexpected end of archive');
      },
    );

    await expectLater(
      installer.install(),
      throwsA(
        isA<ObjectBoxSetupException>().having(
          (error) => error.message,
          'message',
          contains('invalid or truncated'),
        ),
      ),
    );
  });

  test(
    'requests only the exact library member and rejects its absence',
    () async {
      final context = await _TestContext.create();
      addTearDown(context.dispose);
      String? requestedMember;
      final installer = context.installer(
        extractor: (archive, member, destination) async {
          requestedMember = member;
          throw ObjectBoxSetupException('missing $member');
        },
      );

      await expectLater(
        installer.install(),
        throwsA(isA<ObjectBoxSetupException>()),
      );
      expect(requestedMember, 'lib/libobjectbox.so');
    },
  );

  test('surfaces a read-only destination without leaving a marker', () async {
    final context = await _TestContext.create();
    addTearDown(context.dispose);
    final installer = context.installer(
      atomicInstaller: (source, destination) async {
        throw FileSystemException('Read-only file system', destination.path);
      },
    );

    await expectLater(
      installer.install(),
      throwsA(
        isA<ObjectBoxSetupException>().having(
          (error) => error.message,
          'message',
          contains('Read-only file system'),
        ),
      ),
    );
    expect(
      await File(
        '${context.root.path}/tool/objectbox_native_fixture/lib/'
        '.objectbox-vm.json',
      ).exists(),
      isFalse,
    );
  });

  test('installs through paths containing spaces and Unicode', () async {
    final outer = await Directory.systemTemp.createTemp('dartitect path ');
    final root = Directory('${outer.path}/fixture çã 漢字');
    await root.create(recursive: true);
    final context = await _TestContext.create(root: root);
    addTearDown(context.dispose);

    final result = await context.installer().install();

    expect(result.library.path, contains('fixture çã 漢字'));
    expect(await result.library.readAsBytes(), context.libraryBytes);
  });
}

final class _TestContext {
  _TestContext({required this.root, required this.scratch});

  final Directory root;
  final Directory scratch;
  final archiveBytes = utf8.encode('deterministic fake archive');
  final libraryBytes = utf8.encode('deterministic native library');

  static Future<_TestContext> create({Directory? root}) async {
    final scratch = await Directory.systemTemp.createTemp(
      'dartitect-objectbox-test-',
    );
    final repository = root ?? Directory('${scratch.path}/repository');
    await repository.create(recursive: true);
    return _TestContext(root: repository, scratch: scratch);
  }

  ObjectBoxVmInstaller installer({
    ObjectBoxArtifact? artifact,
    ObjectBoxDownloader? downloader,
    ObjectBoxArchiveExtractor? extractor,
    ObjectBoxAtomicInstaller? atomicInstaller,
  }) {
    final selected = artifact ?? _artifactFor(archiveBytes);
    return ObjectBoxVmInstaller(
      repositoryRoot: root,
      operatingSystem: 'linux',
      architecture: 'x64',
      temporaryRoot: Directory('${scratch.path}/temporary area'),
      artifactSelector: (operatingSystem, architecture) => selected,
      downloader:
          downloader ??
          (source, destination) => destination.writeAsBytes(archiveBytes),
      extractor:
          extractor ??
          (archive, member, destination) {
            expect(member, selected.archiveMember);
            return destination.writeAsBytes(libraryBytes);
          },
      atomicInstaller: atomicInstaller,
      log: (_) {},
    );
  }

  Future<void> dispose() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
    if (!root.path.startsWith(scratch.path)) {
      final outer = root.parent;
      if (await outer.exists()) await outer.delete(recursive: true);
    }
  }
}

ObjectBoxArtifact _artifactFor(List<int> archiveBytes) => ObjectBoxArtifact(
  platform: 'linux-x64',
  archiveName: 'objectbox-linux-x64.tar.gz',
  archiveSha256: sha256.convert(archiveBytes).toString(),
  libraryName: 'libobjectbox.so',
);
