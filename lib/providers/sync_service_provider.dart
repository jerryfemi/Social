import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social/services/sync_service.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService();
});

/// Provider for the count of failed messages
final failedMessageCountProvider = FutureProvider<int>((ref) async {
  final syncService = ref.watch(syncServiceProvider);
  return await syncService.getFailedMessageCount();
});
