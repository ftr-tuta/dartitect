import 'package:objectbox/objectbox.dart';

/// Generated-model fixture used only by native adapter consumer tests.
@Entity()
final class FixtureEntity {
  FixtureEntity({this.id = 0, required this.value});

  @Id()
  int id;

  String value;
}
