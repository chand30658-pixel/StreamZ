# StreamZ TV

A fast Android TV / set-top-box style live-TV client built with Flutter + Dart.

## Stack

- Flutter / Dart
- Better Player for native Android HLS/DASH playback
- Hardware-accelerated Android Media3 underneath the player
- TV-first D-pad and keyboard handling
- Edge-to-edge immersive landscape UI

## Configure API access

Do not commit provider credentials to source control.

Run with:

flutter pub get
flutter run --release --dart-define=JIO_API_KEY=YOUR_KEY --dart-define=JIO_APP_KEY=YOUR_APP_KEY

The app also accepts:
- JIO_API_KEY
- JIO_APP_KEY
- EXTRA_FEED_URL
- WORKER_BASE_URL

The playback layer is generic: it can consume an authorized HLS/DASH source, HTTP headers, and a provider-supplied ClearKey configuration without hardcoding keys in the repository.

## Build Android TV APK

flutter build apk --release --dart-define=JIO_API_KEY=YOUR_KEY --dart-define=JIO_APP_KEY=YOUR_APP_KEY

## TV controls

- 0-9: channel dial
- Left / Channel Down: previous channel
- Right / Channel Up: next channel
- Enter / Center: commit dial or toggle OSD
- Back: close modal, keypad, OSD, then exit
- 0000: live-only channel search
