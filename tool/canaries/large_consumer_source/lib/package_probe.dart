// ignore_for_file: public_member_api_docs

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:dartitect_workmanager/dartitect_workmanager.dart';

const List<Type> largeConsumerPackageProbe = <Type>[
  Result,
  DioJsonClient,
  DriftDatabaseOwner,
  ApplicationHost,
  ObservabilityRuntime,
  SyncEngine,
  DartitectWorkmanagerScheduler,
];
