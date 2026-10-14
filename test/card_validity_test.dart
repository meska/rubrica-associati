import 'package:flutter_test/flutter_test.dart';
import 'package:rubrica_associati/models/card_validity.dart';

void main() {
  group('anno solare (predefinito)', () {
    test('a metà anno: fine anno corrente e successivo', () {
      expect(CardValidity.calendarYear.suggestions(DateTime(2026, 10, 14)), [
        DateTime(2026, 12, 31),
        DateTime(2027, 12, 31),
      ]);
    });
    test('il 31 dicembre stesso la scadenza è ancora oggi', () {
      expect(
        CardValidity.calendarYear.suggestions(DateTime(2026, 12, 31)).first,
        DateTime(2026, 12, 31),
      );
    });
    test('il 1° gennaio parte il nuovo anno', () {
      expect(
        CardValidity.calendarYear.suggestions(DateTime(2027, 1, 1)).first,
        DateTime(2027, 12, 31),
      );
    });
    test('rinnovo anticipato: prosegue dal periodo già pagato', () {
      expect(
        CardValidity.calendarYear
            .suggestions(
              DateTime(2026, 10, 14),
              currentExpiry: DateTime(2026, 12, 31),
            )
            .first,
        DateTime(2027, 12, 31),
      );
    });
    test('tessera scaduta: riparte da oggi', () {
      expect(
        CardValidity.calendarYear
            .suggestions(
              DateTime(2026, 10, 14),
              currentExpiry: DateTime(2024, 12, 31),
            )
            .first,
        DateTime(2026, 12, 31),
      );
    });
  });

  group('data fissa diversa (es. ARCI 30 settembre)', () {
    const arci = CardValidity.fixed(30, 9);
    test('dopo la data salta all\'anno dopo', () {
      expect(arci.suggestions(DateTime(2026, 10, 14)), [
        DateTime(2027, 9, 30),
        DateTime(2028, 9, 30),
      ]);
    });
    test('prima della data usa quella dell\'anno corrente', () {
      expect(
        arci.suggestions(DateTime(2026, 3, 1)).first,
        DateTime(2026, 9, 30),
      );
    });
    test('29 febbraio in un anno non bisestile diventa 28', () {
      const feb = CardValidity.fixed(29, 2);
      expect(
        feb.suggestions(DateTime(2026, 3, 1)).first,
        DateTime(2027, 2, 28),
      );
    });
  });

  group('12 mesi dal rinnovo', () {
    const twelve = CardValidity.twelveMonths();
    test('stesso giorno dell\'anno dopo', () {
      expect(twelve.suggestions(DateTime(2026, 10, 14)), [
        DateTime(2027, 10, 14),
      ]);
    });
    test('29 febbraio bisestile', () {
      expect(twelve.suggestions(DateTime(2028, 2, 29)), [
        DateTime(2029, 2, 28),
      ]);
    });
    test('rinnovo anticipato aggiunge 12 mesi alla scadenza', () {
      expect(
        twelve
            .suggestions(
              DateTime(2026, 10, 14),
              currentExpiry: DateTime(2026, 11, 20),
            )
            .first,
        DateTime(2027, 11, 20),
      );
    });
  });

  group('salvataggio', () {
    test('andata e ritorno', () {
      for (final v in const [
        CardValidity.fixed(31, 12),
        CardValidity.fixed(30, 9),
        CardValidity.twelveMonths(),
      ]) {
        expect(CardValidity.fromStorage(v.toStorage()), v);
      }
    });
    test('valori assenti o non validi danno l\'anno solare', () {
      expect(CardValidity.fromStorage(null), CardValidity.calendarYear);
      expect(CardValidity.fromStorage('boh'), CardValidity.calendarYear);
      expect(
        CardValidity.fromStorage('fixed:13-40'),
        CardValidity.calendarYear,
      );
    });
  });
}
