# Rubrica Associati

<p align="center">
  <img src="assets/branding/rubrica-associati-logo.png" width="180" alt="Logo Rubrica Associati">
</p>

App Flutter open source per gestire gli associati di un centro pensionati o di una piccola associazione da telefono o PC.

L'app non invia dati a server e non richiede account o connessione Internet. I dati escono dal dispositivo soltanto quando l'utente sceglie esplicitamente di esportare e condividere un backup.

## Funzioni

- elenco associati ordinato per cognome e nome;
- ricerca immediata per nome, cognome, telefono o numero tessera;
- scheda con telefono, numero e scadenza tessera, data di nascita e note;
- chiamata rapida tramite il dialer del telefono;
- inserimento, modifica ed eliminazione manuale;
- esportazione dell'intera rubrica in un file portabile `.rubrica`;
- condivisione tramite File, AirDrop, email, messaggistica o servizi disponibili sul telefono;
- reimportazione del backup su iOS e Android senza alcun server;
- importazione da Excel `.xlsx` e CSV;
- aggiornamento dei duplicati riconosciuti dal numero tessera o dal telefono;
- evidenza delle tessere scadute;
- interfaccia italiana per iOS, Android e Windows.

## Condivisione tra dispositivi

Dal menu scegli **Condividi rubrica**. L'app crea un backup come `rubrica-associati-2026-07-16.rubrica` e apre il pannello di condivisione del sistema. Il file può essere salvato in File/Drive, inviato via email o messaggistica e poi importato dall'altro dispositivo con **Importa rubrica / Excel**.

Il backup è versionato e comprende nome, cognome, telefono, numero e scadenza tessera, data di nascita e note. In importazione i record esistenti vengono riconosciuti dal numero tessera o dal telefono e aggiornati senza cancellare campi già valorizzati.

Non è una sincronizzazione automatica in tempo reale: chi riceve un file più recente deve importarlo. Questo mantiene l'app indipendente da iCloud e utilizzabile allo stesso modo su Android e iOS.

## Importazione Excel / CSV

La prima riga deve contenere le intestazioni. Sono riconosciute queste colonne, anche con alcune varianti comuni:

| Colonna | Esempio |
| --- | --- |
| Nome | Maria |
| Cognome | Rossi |
| Telefono | 333 1234567 |
| Numero tessera | A001 |
| Scadenza tessera | 31/12/2027 |
| Data di nascita | 15/04/1952 |
| Note | Volontaria |

È disponibile un file pronto da copiare in [examples/associati-esempio.csv](examples/associati-esempio.csv).

Le date accettate sono `gg/mm/aaaa`, `gg-mm-aaaa` e `aaaa-mm-gg`. Nei file Excel sono accettate anche le vere celle data. Per conservare eventuali zeri iniziali, conviene formattare telefono e numero tessera come testo in Excel.

## Sviluppo

Requisiti: Flutter stable e gli strumenti di compilazione Android/iOS.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Build Android:

```bash
flutter build appbundle --release
```

Build iOS:

```bash
flutter build ipa --release
```

Build Windows (da un computer Windows con Visual Studio e il workload C++ desktop):

```powershell
flutter build windows --release
```

Ad ogni push GitHub Actions compila anche una versione portabile Windows e la pubblica come artefatto ZIP del workflow.

Per distribuire su App Store occorrono un account Apple Developer, un bundle identifier definitivo e la firma configurata in Xcode.

## Privacy e backup

Il database SQLite si trova nell'area privata dell'app. Disinstallare l'app elimina normalmente anche i dati locali. Prima dell'uso operativo è consigliato conservare il foglio Excel originale come backup protetto e limitare l'accesso al telefono con codice o biometria.

I file `.rubrica` contengono dati personali in formato JSON leggibile e non sono cifrati. Devono quindi essere condivisi solo con persone autorizzate e conservati in una posizione protetta.

Questa versione trasferisce i dati manualmente tramite file e non li sincronizza automaticamente. Un'eventuale sincronizzazione in tempo reale dovrà essere progettata con autenticazione, autorizzazioni e cifratura adeguate ai dati personali trattati.

## Licenza

[MIT](LICENSE)
