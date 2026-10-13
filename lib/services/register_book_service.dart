import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';

/// Etichette (localizzate dal chiamante) per l'export del libro soci.
class RegisterBookLabels {
  const RegisterBookLabels({
    required this.entity,
    required this.address,
    required this.taxCode,
    required this.representative,
    required this.year,
    required this.generatedOn,
    required this.number,
    required this.admitted,
    required this.ceased,
    required this.empty,
    required this.causes,
  });

  final String entity;
  final String address;
  final String taxCode;
  final String representative;
  final String year;
  final String generatedOn;
  final String number;
  final String admitted;
  final String ceased;
  final String empty;
  final Map<CessationCause, String> causes;
}

/// Prepara il contenuto del libro soci per un anno (date in AAAA-MM-GG,
/// uguali in ogni lingua). Solo logica: il PDF lo produce ArchivePdfService.
class RegisterBookService {
  const RegisterBookService();

  /// Righe del libro valide in almeno un giorno dell'anno [year]. Il numero
  /// progressivo è quello originale del libro.
  List<RegisterEntry> entriesForYear(List<RegisterEntry> entries, int year) {
    final start = '${year.toString().padLeft(4, '0')}-01-01';
    final end = '${year.toString().padLeft(4, '0')}-12-31';
    return entries
        .where(
          (x) =>
              x.admissionDate.compareTo(end) <= 0 &&
              (x.cessationDate == null ||
                  x.cessationDate!.compareTo(start) >= 0),
        )
        .toList(growable: false);
  }

  /// Anni selezionabili, dal più recente al primo anno di ammissione.
  List<int> availableYears(List<RegisterEntry> entries, DateTime now) {
    var first = now.year;
    for (final x in entries) {
      final y = int.tryParse(x.admissionDate.substring(0, 4));
      if (y != null && y < first) first = y;
    }
    return [for (var y = now.year; y >= first; y--) y];
  }

  List<String> lines({
    required List<RegisterEntry> entries,
    required int year,
    required EntityProfile profile,
    required RegisterBookLabels labels,
    required DateTime generated,
  }) {
    final out = <String>[
      '${labels.entity}: ${profile.name}',
      if (profile.address.isNotEmpty) '${labels.address}: ${profile.address}',
      if (profile.taxCode.isNotEmpty) '${labels.taxCode}: ${profile.taxCode}',
      if (profile.legalRepresentative.isNotEmpty)
        '${labels.representative}: ${profile.legalRepresentative}',
      '${labels.year}: $year',
      '${labels.generatedOn}: ${RegisterRepository.todayIso(generated)}',
      '',
    ];
    final rows = entriesForYear(entries, year);
    if (rows.isEmpty) {
      out.add(labels.empty);
      return out;
    }
    for (final x in rows) {
      final name = '${x.lastName} ${x.firstName}'.trim();
      final buffer = StringBuffer(
        '${labels.number} ${x.progressiveNumber} — $name — '
        '${labels.admitted} ${x.admissionDate}',
      );
      if (x.cessationDate != null) {
        buffer.write(' — ${labels.ceased} ${x.cessationDate}');
        final cause = x.cessationCause == null
            ? null
            : labels.causes[x.cessationCause];
        if (cause != null) buffer.write(' ($cause)');
      }
      out.add(buffer.toString());
    }
    return out;
  }
}
