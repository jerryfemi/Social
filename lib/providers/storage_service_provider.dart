import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social/services/storage_service.dart';

final storageServiceProvider = Provider<StorageService>((ref) => StorageService());
