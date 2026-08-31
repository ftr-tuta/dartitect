import 'dart:io';

String platformCachePath(String root) =>
    Platform.isWindows ? '$root\\cache' : '$root/cache';
