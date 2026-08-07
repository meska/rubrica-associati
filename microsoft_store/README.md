# Screenshot Microsoft Store

I testi della scheda sono versionati in `metadata/` per italiano, inglese,
francese e tedesco. Vanno copiati nella submission Partner Center mantenendo
la disponibilità mondiale e usando l'inglese come fallback per gli altri
mercati. Il pacchetto MSIX non contiene mance native: il comando di supporto
apre Ko-fi nel browser esterno.

L'MSIX e il relativo checksum vanno creati su una VM Windows privata o tramite
un canale privato e consegnati direttamente a Partner Center. I workflow e gli
artefatti GitHub pubblici producono soltanto lo ZIP portatile Windows con il
suo checksum: l'MSIX Store non deve mai transitare da GitHub.

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

Prima di creare una submission si può verificare la completezza dei cataloghi
e degli screenshot con:

```bash
./scripts/validate-release-readiness.sh
```
