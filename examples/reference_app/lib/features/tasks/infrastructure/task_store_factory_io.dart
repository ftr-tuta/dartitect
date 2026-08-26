import '../application/offline_task_store.dart';
import 'objectbox_offline_task_store.dart';

/// Native platforms use the real generated ObjectBox model.
Future<OfflineTaskStore> openPlatformTaskStore({String? directoryPath}) =>
    ObjectBoxOfflineTaskStore.open(directoryPath: directoryPath);
