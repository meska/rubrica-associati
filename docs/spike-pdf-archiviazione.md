# Spike L5 — PDF «vicino a PDF/A»

Servizio: `lib/services/archive_pdf_service.dart` (pacchetto `pdf` 3.12, Apache-2.0; font Roboto Regular, Apache-2.0, in `assets/fonts`).

## Cosa fa
- PDF 1.4, senza compressione stream, senza cifratura, senza trasparenze (test dedicati).
- Font TTF incorporato (subset) per tutto il testo.
- Metadati XMP (titolo, ente, data, strumento) con escape corretto; nessuna dichiarazione `pdfaid`.
- «Pagina x di y» in ogni pagina (MultiPage).
- SHA-256 del contenuto (righe) stampata in ogni pagina; SHA-256 dell'intero file restituita a parte (non può stare nel file stesso).

## Cosa manca rispetto a PDF/A pieno
- OutputIntent con profilo colore sRGB (ICC): non incluso per licenza/peso; senza di esso i colori DeviceRGB non sono conformi.
- Il pacchetto scrive `/Version/1.7` nel catalogo e il Producer nell'Info dict con URL: non coincide con l'XMP (PDF/A richiede coerenza Info↔XMP).
- Nessuna validazione con veraPDF; ToUnicode del font non verificata.
- Data di creazione nell'Info dict e nell'XMP in formati diversi.

Decisione Marco 12/10: la conformità perfetta non serve. Nell'app usare «archiviazione PDF», mai «PDF/A».
Prossimo (L6): export per anno che usa il servizio con intestazione ente.
