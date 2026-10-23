import 'dart:convert';

import 'package:book_guard_app/src/guard_api.dart';
import 'package:book_guard_app/src/guard_state.dart';

/// Where [GuardApi.fetchState] keeps the last snapshot on the device.
const snapshotFile = 'state.json';

/// The last `state.json` fetched, so the app still shows where the reading
/// stands with no network at all.
extension Snapshot on GuardApi {
  /// The last snapshot fetched, for when the PC cannot be reached.
  Future<GuardState?> cachedState() async {
    final raw = await store.read(snapshotFile);
    if (raw == null) return null;
    return GuardState.fromJson(
      jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
    );
  }
}
