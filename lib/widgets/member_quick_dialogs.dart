import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/models/card_validity.dart';

String formatShortDate(DateTime d, String locale) =>
    DateFormat.yMd(locale).format(d);

String describeCardRule(CardValidity rule, AppLocalizations strings) {
  if (rule.mode == CardValidityMode.twelveMonths) {
    return strings.cardRuleDescTwelve;
  }
  // L'anno fisso serve solo per formattare giorno e mese.
  final date = DateFormat.MMMMd(
    strings.localeName,
  ).format(DateTime(2001, rule.month, rule.day));
  return strings.cardRuleDescFixed(date);
}

class CardDialogResult {
  const CardDialogResult({required this.number, required this.expiry});
  final String number;
  final DateTime expiry;
}

/// Finestra rapida per aggiungere o rinnovare la tessera: numero e scadenza
/// con scorciatoie calcolate dalla regola dell'ente.
Future<CardDialogResult?> showCardDialog(
  BuildContext context, {
  required bool renewing,
  required String initialNumber,
  required DateTime? currentExpiry,
  required CardValidity validity,
  required Future<void> Function(CardValidity) onValidityChanged,
  DateTime? today,
}) => showDialog<CardDialogResult>(
  context: context,
  builder: (_) => _CardDialog(
    renewing: renewing,
    initialNumber: initialNumber,
    currentExpiry: currentExpiry,
    validity: validity,
    onValidityChanged: onValidityChanged,
    today: today ?? DateTime.now(),
  ),
);

class _CardDialog extends StatefulWidget {
  const _CardDialog({
    required this.renewing,
    required this.initialNumber,
    required this.currentExpiry,
    required this.validity,
    required this.onValidityChanged,
    required this.today,
  });

  final bool renewing;
  final String initialNumber;
  final DateTime? currentExpiry;
  final CardValidity validity;
  final Future<void> Function(CardValidity) onValidityChanged;
  final DateTime today;

  @override
  State<_CardDialog> createState() => _CardDialogState();
}

class _CardDialogState extends State<_CardDialog> {
  late final TextEditingController _number = TextEditingController(
    text: widget.initialNumber,
  );
  late CardValidity _validity = widget.validity;
  DateTime? _chosen;
  DateTime? _custom;

  List<DateTime> get _suggestions =>
      _validity.suggestions(widget.today, currentExpiry: widget.currentExpiry);

  @override
  void initState() {
    super.initState();
    _chosen = _suggestions.first;
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _pickCustom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _chosen ?? widget.today,
      firstDate: DateTime(2000),
      lastDate: DateTime(widget.today.year + 20),
    );
    if (picked != null) {
      setState(() {
        _custom = picked;
        _chosen = picked;
      });
    }
  }

  Future<void> _changeRule() async {
    final next = await showCardRuleDialog(context, _validity);
    if (next == null) return;
    await widget.onValidityChanged(next);
    setState(() {
      _validity = next;
      _custom = null;
      _chosen = _suggestions.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final locale = strings.localeName;
    final options = _suggestions;
    return AlertDialog(
      title: Text(widget.renewing ? strings.renewCard : strings.addCard),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _number,
              decoration: InputDecoration(labelText: strings.memberNumber),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),
            Text(
              strings.membershipExpiry,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final d in options)
                  ChoiceChip(
                    label: Text(strings.cardUntil(formatShortDate(d, locale))),
                    selected: _chosen == d && _custom == null,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _chosen = d;
                      _custom = null;
                    }),
                  ),
                ChoiceChip(
                  avatar: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(
                    _custom == null
                        ? strings.cardOtherDate
                        : strings.cardUntil(formatShortDate(_custom!, locale)),
                  ),
                  selected: _custom != null,
                  showCheckmark: false,
                  onSelected: (_) => _pickCustom(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              strings.cardRuleLine(describeCardRule(_validity, strings)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _changeRule,
                child: Text(strings.cardRuleChange),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _chosen == null
              ? null
              : () => Navigator.pop(
                  context,
                  CardDialogResult(
                    number: _number.text.trim(),
                    expiry: _chosen!,
                  ),
                ),
          child: Text(strings.save),
        ),
      ],
    );
  }
}

/// Scelta della regola di scadenza delle tessere.
Future<CardValidity?> showCardRuleDialog(
  BuildContext context,
  CardValidity current,
) => showDialog<CardValidity>(
  context: context,
  builder: (_) => _RuleDialog(current: current),
);

enum _RuleChoice { yearEnd, twelve, fixed }

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.current});
  final CardValidity current;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late _RuleChoice _choice =
      widget.current.mode == CardValidityMode.twelveMonths
      ? _RuleChoice.twelve
      : widget.current.isCalendarYear
      ? _RuleChoice.yearEnd
      : _RuleChoice.fixed;
  late int _day = widget.current.day;
  late int _month = widget.current.month;

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2001, _month, _day),
      firstDate: DateTime(2001),
      lastDate: DateTime(2001, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _choice = _RuleChoice.fixed;
        _day = picked.day;
        _month = picked.month;
      });
    }
  }

  CardValidity get _result => switch (_choice) {
    _RuleChoice.yearEnd => CardValidity.calendarYear,
    _RuleChoice.twelve => const CardValidity.twelveMonths(),
    _RuleChoice.fixed => CardValidity.fixed(_day, _month),
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final fixedLabel = DateFormat.MMMMd(
      strings.localeName,
    ).format(DateTime(2001, _month, _day));
    return AlertDialog(
      title: Text(strings.cardRuleTitle),
      content: SingleChildScrollView(
        child: RadioGroup<_RuleChoice>(
          groupValue: _choice,
          onChanged: (v) => setState(() => _choice = v ?? _choice),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<_RuleChoice>(
                value: _RuleChoice.yearEnd,
                title: Text(strings.cardRuleYearEnd),
              ),
              RadioListTile<_RuleChoice>(
                value: _RuleChoice.twelve,
                title: Text(strings.cardRuleTwelve),
              ),
              RadioListTile<_RuleChoice>(
                value: _RuleChoice.fixed,
                title: Text(strings.cardRuleFixed),
                subtitle: _choice == _RuleChoice.fixed
                    ? Text(fixedLabel)
                    : null,
              ),
              if (_choice == _RuleChoice.fixed)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: OutlinedButton.icon(
                      onPressed: _pick,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(strings.cardRulePick),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _result),
          child: Text(strings.save),
        ),
      ],
    );
  }
}

/// Conferma dell'ammissione di un solo socio nel libro soci.
/// Ritorna la data AAAA-MM-GG scelta, o null se annullato.
Future<String?> showAdmitOneDialog(
  BuildContext context, {
  required String name,
  required DateTime? joinDate,
  DateTime? today,
}) => showDialog<String>(
  context: context,
  builder: (_) => _AdmitOneDialog(
    name: name,
    joinDate: joinDate,
    today: today ?? DateTime.now(),
  ),
);

class _AdmitOneDialog extends StatefulWidget {
  const _AdmitOneDialog({
    required this.name,
    required this.joinDate,
    required this.today,
  });
  final String name;
  final DateTime? joinDate;
  final DateTime today;

  @override
  State<_AdmitOneDialog> createState() => _AdmitOneDialogState();
}

class _AdmitOneDialogState extends State<_AdmitOneDialog> {
  late DateTime _date = widget.joinDate ?? widget.today;

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(strings.registerInBook),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.bookAdmitOneBody(widget.name)),
            const SizedBox(height: 10),
            // Colonna e non riga: con il testo ingrandito il pulsante non sfora.
            Text(
              strings.bookAdmitDate(formatShortDate(_date, strings.localeName)),
            ),
            if (widget.joinDate == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(1900),
                      lastDate: widget.today,
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: Text(strings.bookAdmitChangeDate),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              strings.bookAdmitNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _iso(_date)),
          child: Text(strings.bookAdmitConfirm),
        ),
      ],
    );
  }
}
