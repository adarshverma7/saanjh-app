import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'frontend/state/user_store.dart';

// Must be a top-level function — called by FCM when the app is terminated.
// No UI operations allowed here; Firebase is the only safe API to call.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // FCM shows the notification automatically from the `notification` field.
  // Data-only messages can be processed here if needed in the future.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register the background message handler before the app starts.
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

  // Request notification permission (Android 13+ / iOS).
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );

  // Restore auth session from secure storage.
  await UserStore.instance.init();

  runApp(const SaanjhApp());
}
