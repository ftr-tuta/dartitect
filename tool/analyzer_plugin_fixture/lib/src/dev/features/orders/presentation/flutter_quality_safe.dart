import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter_testing/dartitect_flutter_testing.dart' as qa;
import 'package:flutter/widgets.dart';

@qa.DartitectPreviewMatrix()
Widget safePreview() => const Text('synthetic');

final class SafeViewModel extends DartitectViewModel {
  @override
  Future<void> disposeAsync() async {}
}

final class SafeViewModelPage extends StatelessWidget {
  const SafeViewModelPage();

  @override
  Widget build(BuildContext context) =>
      ViewModelHost<SafeViewModel>.create(create: SafeViewModel.new);
}

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
