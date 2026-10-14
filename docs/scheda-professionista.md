# Scheda per il professionista (commercialista / consulente Terzo settore / CSV)

Documento di lavoro per far verificare il modulo «Libro soci» e «Registro volontari» di Rubrica Associati (v1.9.0). **Non è un parere legale e l'app non dichiara conformità a norma.** Fonti e analisi: dossier interno `libro-soci-requisiti-legali.md` (verifica del 12/10/2026).

## 1. Cosa fa l'app
- **Libro soci**: registro append-only (nessuna cancellazione fisica, trigger SQLite bloccano UPDATE/DELETE). Ammissione, cessazione con causa (recesso, esclusione, decadenza, decesso, altro), correzione = nuova annotazione datata, riammissione = nuova riga.
- Numero progressivo per data di ammissione; intestazione con dati dell'ente (indirizzo, CF, rappresentante) su ogni pagina; «pagina x di y».
- Campi socio: nome, data di iscrizione, codice fiscale, luogo di nascita (facoltativi).
- **Export per anno** in PDF («archiviazione PDF», non PDF/A pieno) con SHA-256 del contenuto in ogni pagina e SHA-256 del file mostrata a schermo.
- **Chiusura annuale**: l'app esporta il libro; il legale rappresentante lo firma digitalmente e lo marca temporalmente con il proprio strumento; l'app archivia il file firmato (.pdf/.p7m, max 50 MB) con impronta SHA-256, ne verifica l'integrità nel tempo e ricorda gli anni senza chiusura. Un file sostituito non cancella il precedente.
- **Elenco soci ridotto** (solo nome e qualità «Socio») con export CSV nominativo, separato dalla vista completa (rubrica con residenza, contatti, CF).
- **Registro volontari** (DM 6/10/2021 art. 3): codice fiscale oppure generalità + luogo e data di nascita, residenza/domicilio, data inizio e cessazione; sezione separata per i volontari occasionali con progressivi propri; export PDF con le stesse impronte.
- Dati solo sul dispositivo, nessun server.

## 2. Cosa NON fa
- Non firma né marca temporalmente per l'ente e **non verifica la validità della firma** del file archiviato.
- Non è PDF/A certificato: mancano OutputIntent ICC, coerenza Info↔XMP, validazione veraPDF.
- Non gestisce domanda di ammissione, delibera dell'organo, comunicazione all'interessato, motivazione del rigetto (art. 23 CTS): c'è solo l'annotazione dell'ammissione/cessazione.
- Non gestisce libri delle adunanze e verbali (assemblea, organi): fuori perimetro.
- Non modella obbligo assicurativo dei volontari (art. 18 CTS) né conservazione documenti assicurativi (≥10 anni, art. 4 c.2 DM).
- Non distingue tipi di ente (ODV, APS, ASD) né categorie di socio: la «qualità» è unica.
- Nessuna gestione di permessi: la vista completa è accessibile a chi usa l'app sul dispositivo; non c'è login per ruolo.
- Non include nel backup `.rubrica` i file di chiusura annuale né il registro volontari (il backup contiene i soci con i campi nuovi; i vecchi backup restano leggibili). Il backup oggi **non è cifrato**.
- Non applica un termine di conservazione né cancellazione automatica.

## 3. Domande aperte (dossier §7)
1. L'art. 2215-bis c.c. (firma digitale + marcatura temporale almeno annuale) è accettato in pratica, per analogia, per i libri sociali degli ETS? Va bene la cadenza annuale o i CSV/le reti associative suggeriscono altro?
2. Contenuto minimo del libro per ODV e APS e obblighi statutari/regionali: i campi attuali (nome, data iscrizione, CF, luogo di nascita, cessazione con causa) bastano?
3. Per quanto tempo va conservato il libro soci (non risulta un termine di legge)? Va cancellato o anonimizzato dopo la cessazione?
4. Codice fiscale nel libro: base giuridica privacy e minimizzazione (il campo è facoltativo; nessuna fonte del Garante letta).
5. Basta come «elenco soci» per il diritto di esame (nota Min. Lavoro prot. 5003/2026) una vista con nome e qualità, esportabile in CSV? Chi deve poter vedere la vista completa?
6. Per associazioni non ETS (centri pensionati, ASD) il libro è facoltativo: ci sono rischi nel proporlo comunque?
7. Il registro volontari elettronico, con export PDF + firma/marcatura annuale (DM art. 3 c.2), soddisfa «inalterabilità e data certa»? Occorre un'azione dell'ente oltre all'archivio delle chiusure?
8. Il backup non cifrato con dati personali (CF, residenza) è accettabile o va cifrato con password?

## 4. Da portare al colloquio
Export PDF di esempio del libro e dei volontari, schermata «Elenco soci», chiusura annuale archiviata con verifica impronta.
