# Piano di distribuzione

La versione canonica è quella in `pubspec.yaml`. L'app è completa e gratuita,
senza pubblicità o funzioni bloccate. Italiano, inglese, francese e tedesco
sono le lingue supportate dall'app e dalle schede; negli altri mercati si usa
la scheda inglese come fallback.

## Canali

- Apple App Store: disponibilità mondiale, prezzo gratuito, quattro mance
  consumabili facoltative e rilascio automatico dopo l'approvazione.
- Google Play: disponibilità mondiale, prezzo gratuito, gli stessi quattro
  consumabili e rollout completo dopo l'approvazione.
- Microsoft Store: disponibilità mondiale, prezzo gratuito, nessun acquisto
  nativo; il comando di supporto apre Ko-fi nel browser.
- GitHub Releases: ZIP Windows, AppImage, DEB e archivio portatile Linux, tutti
  riferiti allo stesso tag e accompagnati dai checksum SHA-256. L'MSIX viene
  creato e consegnato a Partner Center soltanto da una VM o un canale privato;
  non transita nei workflow, negli artefatti o nelle release GitHub pubbliche.

I testi Apple, Google e Microsoft sono rispettivamente in `app_store/metadata`,
`play_store/metadata` e `microsoft_store/metadata`. I nomi e le descrizioni
localizzate dei consumabili mobili sono in `mobile-tip-products.csv`; i prezzi
sono riferimenti in euro e gli store devono applicare i propri prezzi locali.

## Controlli esterni prima dell'invio

1. Selezionare e verificare il provider Meskatech autorizzato prima di leggere
   o modificare la scheda.
2. Confermare prezzo gratuito e tutti i territori disponibili in ciascuno
   store; non limitare la distribuzione alle sole quattro lingue.
3. Creare o verificare i quattro consumabili Apple e Google con gli ID esatti
   del CSV, tutte le localizzazioni, disponibilità mondiale e prezzi locali
   equivalenti ai riferimenti.
4. Revisionare visivamente e caricare testi e immagini mobili per tutte le
   quattro lingue. La presenza dei file localizzati nel repository non prova
   che siano corretti o già associati alle rispettive schede store.
5. Eseguire uno smoke test reale degli acquisti sandbox su iOS e Android e del
   collegamento Ko-fi su Windows e Linux.
6. Verificare firma, versione e checksum degli artefatti finali, quindi inviare
   le release e controllarne lo stato pubblico.

Il controllo repository-side si esegue con
`./scripts/validate-release-readiness.sh`; non sostituisce le verifiche dei
territori, dei prodotti e delle firme dentro le console.
