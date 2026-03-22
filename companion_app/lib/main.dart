import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/auth/secure_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = SecureStorageService();

  // Restore base URL from previous session (if any).
  final savedBaseUrl = await storage.readBaseUrl();
  ApiClient.init(
    baseUrl: savedBaseUrl ?? 'http://localhost:8080',
    storage: storage,
  );

  runApp(CompanionApp(storage: storage));
}
