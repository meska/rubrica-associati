import 'package:rubrica_associati/models/member.dart';

/// Una riga dell'elenco soci ridotto: solo nome e qualità di socio.
class RosterEntry {
  const RosterEntry(this.displayName);
  final String displayName;
}

/// Vista «elenco soci» ridotta: nessun dato personale oltre al nome
/// (niente telefono, residenza, codice fiscale, note).
class RosterService {
  const RosterService();

  List<RosterEntry> entries(List<Member> members) {
    final names =
        members
            .map((m) => '${m.lastName.trim()} ${m.firstName.trim()}'.trim())
            .where((name) => name.isNotEmpty)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.map(RosterEntry.new).toList(growable: false);
  }

  String toCsv(
    List<Member> members, {
    required String nameHeader,
    required String qualityHeader,
    required String qualityValue,
  }) {
    final buffer = StringBuffer()
      ..write('${_cell(nameHeader)},${_cell(qualityHeader)}\r\n');
    for (final entry in entries(members)) {
      buffer.write('${_cell(entry.displayName)},${_cell(qualityValue)}\r\n');
    }
    return buffer.toString();
  }

  static String _cell(String value) {
    var text = value;
    // Evita l'esecuzione di formule nei fogli di calcolo.
    if (RegExp(r'^[=+\-@\t\r]').hasMatch(text)) text = "'$text";
    if (text.contains(RegExp(r'[",\r\n]'))) {
      text = '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }
}
