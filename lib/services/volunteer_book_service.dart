import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/data/volunteer_repository.dart';

/// Etichette (localizzate dal chiamante) per l'export del registro volontari.
class VolunteerBookLabels {
  const VolunteerBookLabels({
    required this.entity,
    required this.address,
    required this.taxCode,
    required this.representative,
    required this.generatedOn,
    required this.number,
    required this.started,
    required this.ceased,
    required this.born,
    required this.residence,
    required this.regularTitle,
    required this.occasionalTitle,
    required this.empty,
  });

  final String entity;
  final String address;
  final String taxCode;
  final String representative;
  final String generatedOn;
  final String number;
  final String started;
  final String ceased;
  final String born;
  final String residence;
  final String regularTitle;
  final String occasionalTitle;
  final String empty;
}

/// Prepara le righe del registro volontari per ArchivePdfService: sezione dei
/// volontari e, separata, quella degli occasionali (ciascuna col proprio
/// progressivo). Date in AAAA-MM-GG, uguali in ogni lingua.
class VolunteerBookService {
  const VolunteerBookService();

  List<String> lines({
    required List<VolunteerEntry> entries,
    required EntityProfile profile,
    required VolunteerBookLabels labels,
    required DateTime generated,
  }) {
    final out = <String>[
      '${labels.entity}: ${profile.name}',
      if (profile.address.isNotEmpty) '${labels.address}: ${profile.address}',
      if (profile.taxCode.isNotEmpty) '${labels.taxCode}: ${profile.taxCode}',
      if (profile.legalRepresentative.isNotEmpty)
        '${labels.representative}: ${profile.legalRepresentative}',
      '${labels.generatedOn}: ${RegisterRepository.todayIso(generated)}',
      '',
    ];
    if (entries.isEmpty) {
      out.add(labels.empty);
      return out;
    }
    final regular = entries.where((e) => !e.occasional).toList();
    final occasional = entries.where((e) => e.occasional).toList();
    void section(String title, List<VolunteerEntry> list) {
      out.add(title);
      for (final e in list) {
        out.add(_row(e, labels));
      }
      out.add('');
    }

    if (regular.isNotEmpty) section(labels.regularTitle, regular);
    if (occasional.isNotEmpty) section(labels.occasionalTitle, occasional);
    return out;
  }

  String _row(VolunteerEntry e, VolunteerBookLabels l) {
    final parts = <String>[
      '${l.number} ${e.progressiveNumber}',
      '${e.lastName} ${e.firstName}'.trim(),
      if (e.taxCode.isNotEmpty) e.taxCode,
      if (e.birthPlace.isNotEmpty || e.birthDate.isNotEmpty)
        '${l.born} ${e.birthPlace} ${e.birthDate}'.replaceAll('  ', ' ').trim(),
      '${l.residence} ${e.residence}',
      '${l.started} ${e.startDate}',
      if (e.endDate != null) '${l.ceased} ${e.endDate}',
    ];
    return parts.join(' — ');
  }
}
