import 'package:book_guard_app/src/local_store.dart';

/// The web build keeps nothing: it is served by the PC it talks to.
Future<LocalStore> createLocalStore() async => MemoryStore();
