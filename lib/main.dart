import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'frontend/state/user_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Restore auth session from secure storage
  await UserStore.instance.init();

  runApp(const SaanjhApp());
}
