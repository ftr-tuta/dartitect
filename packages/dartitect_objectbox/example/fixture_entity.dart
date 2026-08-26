import 'package:objectbox/objectbox.dart';

/// Consumer-owned entity used by the generated publishable example model.
@Entity()
final class FixtureEntity {
  /// Creates a fixture value.
  FixtureEntity({this.id = 0, required this.value});

  /// ObjectBox identifier assigned on insert.
  @Id()
  int id;

  /// Example payload.
  String value;
}
