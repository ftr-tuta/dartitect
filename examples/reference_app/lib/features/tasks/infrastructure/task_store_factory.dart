import '../application/offline_task_store.dart';
import 'memory_offline_task_store.dart';
import 'task_store_factory_stub.dart'
    if (dart.library.io) 'task_store_factory_io.dart'
    as platform;

/// Opens the platform store, or an explicit deterministic memory store.
Future<OfflineTaskStore> openOfflineTaskStore({
  String? directoryPath,
  bool forceMemory = false,
}) async {
  if (forceMemory) return MemoryOfflineTaskStore();
  return platform.openPlatformTaskStore(directoryPath: directoryPath);
}
