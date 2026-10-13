import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/services/roster_service.dart';
import 'package:share_plus/share_plus.dart';

/// Elenco soci ridotto: nome e qualità di socio, nessun dato personale.
class RosterScreen extends StatelessWidget {
  const RosterScreen({super.key, required this.members});

  final List<Member> members;

  static const _service = RosterService();

  Future<void> _export(BuildContext context) async {
    final strings = AppLocalizations.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final csv = _service.toCsv(
      members,
      nameHeader: strings.rosterNameHeader,
      qualityHeader: strings.rosterQualityHeader,
      qualityValue: strings.rosterQualityMember,
    );
    final directory = await getTemporaryDirectory();
    final file = File(path.join(directory.path, 'elenco-soci.csv'));
    await file.writeAsString('\uFEFF$csv', flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        fileNameOverrides: ['elenco-soci.csv'],
        title: strings.rosterShareTitle,
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final entries = _service.entries(members);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.rosterTitle),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              tooltip: strings.rosterExport,
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: () => _export(context),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(strings.rosterHint),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text(strings.rosterEmpty))
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => ListTile(
                        title: Text(entries[i].displayName),
                        subtitle: Text(strings.rosterQualityMember),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
