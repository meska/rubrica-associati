# Screenshot Microsoft Store

Gli screenshot desktop sono generati dall'interfaccia Flutter reale a
`1366 x 768`, con dati dimostrativi e localizzazione italiana, inglese,
francese e tedesca.

Il test resta escluso dalla suite ordinaria perché usa i font del Flutter SDK e
aggiorna file binari. Per rigenerare tutte le immagini:

```bash
GENERATE_STORE_SCREENSHOTS=1 \
FLUTTER_ROOT=/percorso/del/flutter-sdk \
flutter test --update-goldens test/microsoft_store_screenshot_test.dart
```
