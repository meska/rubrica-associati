class Member {
  const Member({
    this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.memberNumber,
    this.expiryDate,
    this.birthDate,
    required this.notes,
  });

  final int? id;
  final String firstName;
  final String lastName;
  final String phone;
  final String memberNumber;
  final DateTime? expiryDate;
  final DateTime? birthDate;
  final String notes;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final parts = [firstName, lastName].where((value) => value.isNotEmpty);
    return parts.map((value) => value[0].toUpperCase()).take(2).join();
  }

  String get phoneKey => phone.replaceAll(RegExp(r'\D'), '');

  bool get isExpired {
    final expiry = expiryDate;
    if (expiry == null) return false;
    final today = DateTime.now();
    return DateTime(
      expiry.year,
      expiry.month,
      expiry.day,
    ).isBefore(DateTime(today.year, today.month, today.day));
  }

  Member copyWith({int? id}) => Member(
    id: id ?? this.id,
    firstName: firstName,
    lastName: lastName,
    phone: phone,
    memberNumber: memberNumber,
    expiryDate: expiryDate,
    birthDate: birthDate,
    notes: notes,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'first_name': firstName.trim(),
    'last_name': lastName.trim(),
    'phone': phone.trim(),
    'phone_key': phoneKey,
    'member_number': memberNumber.trim(),
    'expiry_date': _dateToStorage(expiryDate),
    'birth_date': _dateToStorage(birthDate),
    'notes': notes.trim(),
  };

  factory Member.fromMap(Map<String, Object?> map) => Member(
    id: map['id'] as int?,
    firstName: map['first_name'] as String? ?? '',
    lastName: map['last_name'] as String? ?? '',
    phone: map['phone'] as String? ?? '',
    memberNumber: map['member_number'] as String? ?? '',
    expiryDate: _dateFromStorage(map['expiry_date'] as String?),
    birthDate: _dateFromStorage(map['birth_date'] as String?),
    notes: map['notes'] as String? ?? '',
  );

  static String? _dateToStorage(DateTime? value) {
    if (value == null) return null;
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
  }

  static DateTime? _dateFromStorage(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
