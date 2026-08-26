import '../application/offline_task_store.dart';
import 'memory_offline_task_store.dart';

/// ObjectBox has no web implementation; preserve the contract in memory.
Future<OfflineTaskStore> openPlatformTaskStore({String? directoryPath}) async =>
    MemoryOfflineTaskStore();
