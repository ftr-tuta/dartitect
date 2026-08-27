class Store {}

class Widget {}

Object getIt() => Object();

void useApplicationTypes() {
  Store();
  Widget();
  getIt();
  final configuration = <String, Object?>{'password': 'local-only'};
  configuration.clear();
}
