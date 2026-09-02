import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../domain/quality_task.dart';
import '../infrastructure/quality_backend.dart' as infra;

final class QualityWidget extends StatefulWidget {
  const QualityWidget();

  @override
  State<QualityWidget> createState() => _QualityWidgetState();
}

final class _QualityWidgetState extends State<QualityWidget> {
  final ScrollController scrollController = ScrollController();
  final SessionRuntimeController<Object, Object> session =
      SessionRuntimeController<Object, Object>();
  final QualityTask task = QualityTask();

  @override
  Widget build(BuildContext context) {
    final infra.NativeTaskStore store = infra.NativeTaskStore();
    final TextEditingController editing = TextEditingController();
    final ValueNotifier<SessionState<Object>> duplicate =
        ValueNotifier<SessionState<Object>>(const SessionState<Object>());
    store.readSync();
    setState(() {
      task.toggle();
    });
    return Text('${editing.hashCode}:${duplicate.hashCode}:$session');
  }

  Future<void> open(BuildContext context) async {
    await Future<void>.delayed(Duration.zero);
    Navigator.of(context);
  }
}
