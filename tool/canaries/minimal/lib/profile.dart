import 'package:dartitect/dartitect.dart';

part 'profile.dartitect.g.dart';

@DartitectValue()
final class Profile extends ValueEquality with _$ProfileDartitect {
  const Profile({required this.id, required this.label});

  final String id;
  final String? label;
}
