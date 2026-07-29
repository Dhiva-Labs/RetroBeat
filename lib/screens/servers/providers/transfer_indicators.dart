import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/server_providers.dart';

/// Jobs neither finished, failed nor cancelled — what every "something is
/// happening" badge in the Servers area counts.
final activeTransferCountProvider = Provider<int>((ref) {
  return ref
      .watch(transferEngineProvider)
      .where((job) => !job.isFinished)
      .length;
});
