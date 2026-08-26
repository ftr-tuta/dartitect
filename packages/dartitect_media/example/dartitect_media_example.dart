import 'package:dartitect/dartitect.dart';
import 'package:dartitect_media/dartitect_media.dart';

Future<void> saveExport(String absolutePath) async {
  final gallery = MethodChannelGalleryMediaService();
  if (await gallery.requestAccess() != GalleryPermissionStatus.authorized)
    return;
  final result = await gallery.saveImage(
    GallerySaveRequest(path: absolutePath, album: 'Exports'),
  );
  if (result case Err<GalleryFailure>()) return;
}
