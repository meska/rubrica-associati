import 'package:rubrica_associati/models/member.dart';

enum MemberFilter { all, inGoodStanding, expired, noExpiry, notInBook }

/// Filtra l'elenco già caricato. [notInBookIds] sono i soci senza alcuna
/// annotazione nel libro soci.
List<Member> applyMemberFilter(
  List<Member> members,
  MemberFilter filter,
  Set<int> notInBookIds,
) => switch (filter) {
  MemberFilter.all => members,
  // In regola = ha una scadenza e non è passata. Senza data non si può dire.
  MemberFilter.inGoodStanding =>
    members
        .where((m) => m.expiryDate != null && !m.isExpired)
        .toList(growable: false),
  MemberFilter.noExpiry =>
    members.where((m) => m.expiryDate == null).toList(growable: false),
  MemberFilter.expired =>
    members.where((m) => m.isExpired).toList(growable: false),
  MemberFilter.notInBook =>
    members
        .where((m) => m.id != null && notInBookIds.contains(m.id))
        .toList(growable: false),
};
