import 'package:rubrica_associati/models/member.dart';

enum MemberFilter { all, inGoodStanding, expired, notInBook }

/// Filtra l'elenco già caricato. [notInBookIds] sono i soci senza alcuna
/// annotazione nel libro soci.
List<Member> applyMemberFilter(
  List<Member> members,
  MemberFilter filter,
  Set<int> notInBookIds,
) => switch (filter) {
  MemberFilter.all => members,
  MemberFilter.inGoodStanding =>
    members.where((m) => !m.isExpired).toList(growable: false),
  MemberFilter.expired =>
    members.where((m) => m.isExpired).toList(growable: false),
  MemberFilter.notInBook =>
    members
        .where((m) => m.id != null && notInBookIds.contains(m.id))
        .toList(growable: false),
};
