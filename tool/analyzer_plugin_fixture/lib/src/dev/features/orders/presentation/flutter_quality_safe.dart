import 'package:dartitect_flutter_testing/dartitect_flutter_testing.dart' as qa;
import 'package:flutter/widgets.dart';

@qa.DartitectPreviewMatrix()
Widget safePreview() => const Text('synthetic');

final class SafeQualityWidget extends StatefulWidget {
  const SafeQualityWidget();

  @override
  State<SafeQualityWidget> createState() => _SafeQualityWidgetState();
}

final class _SafeQualityWidgetState extends State<SafeQualityWidget> {
  final ScrollController scrollController = ScrollController();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    child: Image.network('https://invalid.example/synthetic.png'),
  );

  Future<void> open(BuildContext context) async {
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
    Navigator.of(context);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}
