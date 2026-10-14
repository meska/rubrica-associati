/// Regola con cui scade la tessera di un socio. Nei centri e nelle
/// associazioni italiane convivono più usanze (anno solare, ARCI dal 1°
/// ottobre al 30 settembre, UISP dal 1° settembre, 12 mesi dal rinnovo):
/// la regola è quindi configurabile. Predefinita: anno solare (31 dicembre).
enum CardValidityMode { fixedDate, twelveMonths }

class CardValidity {
  const CardValidity.fixed(this.day, this.month)
    : mode = CardValidityMode.fixedDate;

  const CardValidity.twelveMonths()
    : mode = CardValidityMode.twelveMonths,
      day = 31,
      month = 12;

  /// Anno solare: la tessera scade il 31 dicembre.
  static const calendarYear = CardValidity.fixed(31, 12);

  static const storageKey = 'card_validity';

  final CardValidityMode mode;
  final int day;
  final int month;

  bool get isCalendarYear =>
      mode == CardValidityMode.fixedDate && day == 31 && month == 12;

  String toStorage() =>
      mode == CardValidityMode.twelveMonths ? 'months12' : 'fixed:$month-$day';

  /// Valori non validi o assenti danno l'anno solare.
  static CardValidity fromStorage(String? value) {
    if (value == 'months12') return const CardValidity.twelveMonths();
    final match = RegExp(
      r'^fixed:(\d{1,2})-(\d{1,2})$',
    ).firstMatch(value ?? '');
    if (match == null) return calendarYear;
    final month = int.parse(match.group(1)!);
    final day = int.parse(match.group(2)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return calendarYear;
    return CardValidity.fixed(day, month);
  }

  static DateTime _clamped(int year, int month, int day) {
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > last ? last : day);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Scadenze proposte per un rinnovo o una nuova tessera fatti oggi.
  /// Se la tessera attuale è ancora valida ([currentExpiry] da oggi in poi)
  /// si proseguono i periodi da lì; altrimenti si parte da oggi.
  List<DateTime> suggestions(DateTime today, {DateTime? currentExpiry}) {
    final now = _dateOnly(today);
    final expiry = currentExpiry == null ? null : _dateOnly(currentExpiry);
    final stillValid = expiry != null && !expiry.isBefore(now);

    if (mode == CardValidityMode.twelveMonths) {
      final base = stillValid ? expiry : now;
      return [_clamped(base.year + 1, base.month, base.day)];
    }

    final from = stillValid ? expiry.add(const Duration(days: 1)) : now;
    final thisYear = _clamped(from.year, month, day);
    final first = thisYear.isBefore(from)
        ? _clamped(from.year + 1, month, day)
        : thisYear;
    return [first, _clamped(first.year + 1, month, day)];
  }

  @override
  bool operator ==(Object other) =>
      other is CardValidity &&
      other.mode == mode &&
      other.day == day &&
      other.month == month;

  @override
  int get hashCode => Object.hash(mode, day, month);
}
