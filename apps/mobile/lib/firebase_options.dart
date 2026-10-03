import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD2Toz0swbAIklmTqMzzkx5yMOzB5C5jmQ',
    appId: '1:403758366529:android:8f7f7a79006d1d3adbebc0',
    messagingSenderId: '403758366529',
    projectId: 'philoin-23067',
    storageBucket: 'philoin-23067.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBytdlSKpyDkPC9qvdOLliP6mafHc6ZzrI',
    appId: '1:403758366529:ios:47a09cb3ec4b6480dbebc0',
    messagingSenderId: '403758366529',
    projectId: 'philoin-23067',
    storageBucket: 'philoin-23067.firebasestorage.app',
    iosBundleId: 'com.paditech.mobile',
    iosClientId: '403758366529-smjmomdsaukl77vc2707r8sthpjhd164.apps.googleusercontent.com', 
  );
}
