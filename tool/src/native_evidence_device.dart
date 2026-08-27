import 'dart:convert';

import 'package:crypto/crypto.dart';

const requiredAdbServerSocket = 'tcp:127.0.0.1:5038';

Map<String, String> nativeEvidenceEnvironment(Map<String, String> base) {
  final socket = base['ADB_SERVER_SOCKET'];
  if (socket == null || socket.trim().isEmpty) {
    throw StateError(
      'ADB_SERVER_SOCKET is required and must target the isolated RC.3 server.',
    );
  }
  if (socket != requiredAdbServerSocket) {
    throw StateError(
      'ADB_SERVER_SOCKET must be exactly $requiredAdbServerSocket.',
    );
  }
  return <String, String>{...base, 'ADB_SERVER_SOCKET': socket};
}

NativeDeviceSelection selectPhysicalAndroidDevice({
  required String requestedId,
  required String adbDevicesOutput,
  required List<Map<String, Object?>> flutterDevices,
}) {
  if (requestedId.trim().isEmpty) {
    throw const FormatException('Exactly one --device argument is required.');
  }
  final adbDevices = parseAdbDevices(adbDevicesOutput);
  if (adbDevices.isEmpty) {
    throw StateError('No device is visible through the isolated ADB server.');
  }
  final unavailable = adbDevices.where((device) => device.state != 'device');
  if (unavailable.isNotEmpty) {
    final states = unavailable.map((device) => device.state).toSet().join(', ');
    throw StateError('ADB device is unavailable ($states).');
  }
  if (adbDevices.length != 1) {
    throw StateError(
      'Exactly one device must be connected to the isolated ADB server.',
    );
  }
  if (adbDevices.single.id != requestedId) {
    throw StateError('The selected device is not the isolated ADB device.');
  }

  final androidDevices = flutterDevices
      .where((device) => '${device['targetPlatform']}'.startsWith('android-'))
      .toList();
  if (androidDevices.length != 1 ||
      androidDevices.single['id'] != requestedId) {
    throw StateError(
      'Flutter must select exactly the one isolated Android device.',
    );
  }
  final flutterDevice = androidDevices.single;
  if (flutterDevice['emulator'] != false) {
    throw StateError('Android emulators are forbidden for RC.3 evidence.');
  }
  return NativeDeviceSelection(
    id: requestedId,
    model: '${flutterDevice['name']}'.trim(),
    sdk: '${flutterDevice['sdk']}'.trim(),
    idSha256: digestDeviceId(requestedId),
  );
}

List<AdbDevice> parseAdbDevices(String output) {
  final devices = <AdbDevice>[];
  for (final rawLine in const LineSplitter().convert(output)) {
    final line = rawLine.trim();
    if (line.isEmpty ||
        line.startsWith('List of devices attached') ||
        line.startsWith('* daemon')) {
      continue;
    }
    final fields = line.split(RegExp(r'\s+'));
    if (fields.length < 2) {
      throw const FormatException('Malformed adb devices output.');
    }
    devices.add(AdbDevice(fields[0], fields[1]));
  }
  return devices;
}

void requireAndroidApi34(int apiLevel) {
  if (apiLevel != 34) {
    throw StateError('Physical Android evidence requires API 34 exactly.');
  }
}

String digestDeviceId(String deviceId) =>
    sha256.convert(utf8.encode(deviceId)).toString();

String redactDeviceId(String value, String deviceId) =>
    value.replaceAll(deviceId, '<physical-device>');

final class AdbDevice {
  const AdbDevice(this.id, this.state);

  final String id;
  final String state;
}

final class NativeDeviceSelection {
  const NativeDeviceSelection({
    required this.id,
    required this.model,
    required this.sdk,
    required this.idSha256,
  });

  final String id;
  final String model;
  final String sdk;
  final String idSha256;
}
