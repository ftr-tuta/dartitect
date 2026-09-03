import 'package:dartitect_flutter_testing/dartitect_flutter_testing.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview matrix emits the exact ordered Dartitect device rows', () {
    const matrix = DartitectPreviewMatrix();
    final previews = matrix.previews;

    expect(matrix, isA<MultiPreview>());
    expect(previews, hasLength(4));
    expect(
      previews
          .map(
            (preview) => (
              preview.name,
              preview.size,
              preview.brightness,
              preview.textScaleFactor,
            ),
          )
          .toList(),
      const <(String?, Size?, Brightness?, double?)>[
        ('compact', Size(360, 640), Brightness.light, 1),
        ('compact-200-percent', Size(430, 932), Brightness.dark, 2),
        ('medium', Size(768, 1024), Brightness.light, 1),
        ('expanded', Size(1440, 900), Brightness.light, 1),
      ],
    );
    expect(previews.every((preview) => preview.group == 'Dartitect'), isTrue);
  });

  test('preview matrix does not duplicate accessibility harness concerns', () {
    final previews = const DartitectPreviewMatrix().previews;

    expect(
      previews.every(
        (preview) =>
            preview.wrapper == null &&
            preview.theme == null &&
            preview.localizations == null,
      ),
      isTrue,
    );
    expect(DartitectUiMatrix.standard.scenarios, hasLength(5));
  });
}
