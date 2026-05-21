// Generated for project saanjh-fe1a8
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web not supported');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
            'DefaultFirebaseOptions not configured for ${defaultTargetPlatform.name}');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'AIzaSyAP8-d7QALuP_BVpxfK-dNPUtKSV2491eA',
    appId:             '1:853634976119:android:7002b4c12f24c46d88f972',
    messagingSenderId: '853634976119',
    projectId:         'saanjh-fe1a8',
    storageBucket:     'saanjh-fe1a8.firebasestorage.app',
  );

  // iOS not yet configured — add google-services via GoogleService-Info.plist
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey:            'AIzaSyAP8-d7QALuP_BVpxfK-dNPUtKSV2491eA',
    appId:             '1:853634976119:ios:placeholder',
    messagingSenderId: '853634976119',
    projectId:         'saanjh-fe1a8',
    storageBucket:     'saanjh-fe1a8.firebasestorage.app',
    iosBundleId:       'com.saanjh.saanjh',
  );
}
