import 'package:flutter/material.dart';
import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/main.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/screens/member_detail_screen.dart';
import 'package:rubrica_associati/screens/member_form_screen.dart';

const _page = String.fromEnvironment('SCREENSHOT_PAGE', defaultValue: 'home');

final _members = <Member>[
  Member(
    id: 1,
    firstName: 'Giulia',
    lastName: 'Bianchi',
    phone: '333 7654321',
    secondaryPhone: '049 123456',
    memberNumber: 'A-0142',
    expiryDate: DateTime(2027, 12, 31),
    birthDate: DateTime(1952, 4, 15),
    notes: 'Volontaria del circolo',
  ),
  Member(
    id: 2,
    firstName: 'Carlo',
    lastName: 'De Luca',
    phone: '347 1122334',
    memberNumber: 'A-0188',
    expiryDate: DateTime(2028, 3, 31),
    notes: '',
  ),
  Member(
    id: 3,
    firstName: 'Anna',
    lastName: 'Ferrari',
    phone: '349 5566778',
    memberNumber: 'A-0201',
    expiryDate: DateTime(2027, 9, 30),
    notes: '',
  ),
  Member(
    id: 4,
    firstName: 'Mario',
    lastName: 'Rossi',
    phone: '320 4455667',
    memberNumber: 'A-0256',
    expiryDate: DateTime(2028, 1, 31),
    notes: '',
  ),
  Member(
    id: 5,
    firstName: 'Lucia',
    lastName: 'Verdi',
    phone: '335 7788990',
    memberNumber: 'A-0274',
    expiryDate: DateTime(2027, 11, 30),
    notes: '',
  ),
];

class _PreviewRepository extends MemberRepository {
  @override
  Future<List<Member>> search(String query) async => _members;

  @override
  Future<String> loadOrganizationName() async => 'Circolo Serenità';
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = _PreviewRepository();
  final home = switch (_page) {
    'detail' => MemberDetailScreen(
      member: _members.first,
      repository: repository,
    ),
    'form' => MemberFormScreen(member: _members.first),
    _ => null,
  };

  // Qua ghe xe solo dati inventai par le immagini dello store.
  runApp(RubricaAssociatiApp(repository: repository, home: home));
}
