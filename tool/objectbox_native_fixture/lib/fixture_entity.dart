import 'package:objectbox/objectbox.dart';

/// Generated-model fixture used only by native adapter consumer tests.
@Entity()
final class FixtureEntity {
  /// Creates the provider entity through the evidence-scoped exception.
  FixtureEntity({this.id = 0, required this.value});

  /// ObjectBox identifier assigned on insert.
  @Id()
  int id;

  /// Mutable provider-owned payload.
  String value;
}
