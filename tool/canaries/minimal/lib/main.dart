import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';

final class GreetingService {
  const GreetingService();

  Future<Result<String, String>> load() async => const Ok('packaged');
}

final class ProfileViewModel {
  ProfileViewModel(GreetingService service) : load = Command0(service.load);

  final Command0<String, String> load;

  Future<void> disposeAsync() => load.disposeAsync();
}

final class CompositionRoot {
  CompositionRoot() : profile = ProfileViewModel(const GreetingService());

  final ProfileViewModel profile;

  Future<void> disposeAsync() => profile.disposeAsync();
}

void main() {}
