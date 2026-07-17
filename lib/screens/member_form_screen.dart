import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class MemberFormScreen extends StatefulWidget {
  const MemberFormScreen({super.key, this.member});

  final Member? member;

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _secondaryPhone;
  late final TextEditingController _memberNumber;
  late final TextEditingController _notes;
  DateTime? _expiryDate;
  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    _firstName = TextEditingController(text: member?.firstName ?? '');
    _lastName = TextEditingController(text: member?.lastName ?? '');
    _phone = TextEditingController(text: member?.phone ?? '');
    _secondaryPhone = TextEditingController(text: member?.secondaryPhone ?? '');
    _memberNumber = TextEditingController(text: member?.memberNumber ?? '');
    _notes = TextEditingController(text: member?.notes ?? '');
    _expiryDate = member?.expiryDate;
    _birthDate = member?.birthDate;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _secondaryPhone.dispose();
    _memberNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _chooseDate({required bool expiry}) async {
    final strings = AppLocalizations.of(context);
    final current = expiry ? _expiryDate : _birthDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: expiry ? DateTime(2100) : DateTime.now(),
      helpText: expiry
          ? strings.membershipExpiryPicker
          : strings.dateOfBirthPicker,
    );
    if (selected == null) return;
    setState(() {
      if (expiry) {
        _expiryDate = selected;
      } else {
        _birthDate = selected;
      }
    });
  }

  void _save() {
    final strings = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_firstName.text.trim().isEmpty && _lastName.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.enterFirstOrLastName)));
      return;
    }
    Navigator.of(context).pop(
      Member(
        id: widget.member?.id,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.trim(),
        secondaryPhone: _secondaryPhone.text.trim(),
        memberNumber: _memberNumber.text.trim(),
        expiryDate: _expiryDate,
        birthDate: _birthDate,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.member == null ? strings.newMember : strings.edit),
        actions: [TextButton(onPressed: _save, child: Text(strings.save))],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstName,
                      decoration: InputDecoration(labelText: strings.firstName),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [LengthLimitingTextInputFormatter(100)],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastName,
                      decoration: InputDecoration(labelText: strings.lastName),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [LengthLimitingTextInputFormatter(100)],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: InputDecoration(
                  labelText: strings.phone,
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _secondaryPhone,
                decoration: InputDecoration(
                  labelText: strings.secondaryPhone,
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _memberNumber,
                decoration: InputDecoration(
                  labelText: strings.memberNumber,
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
                inputFormatters: [LengthLimitingTextInputFormatter(100)],
              ),
              const SizedBox(height: 12),
              _DateField(
                label: strings.membershipExpiry,
                value: _expiryDate,
                icon: Icons.event_available_outlined,
                onTap: () => _chooseDate(expiry: true),
                onClear: () => setState(() => _expiryDate = null),
              ),
              const SizedBox(height: 12),
              _DateField(
                label: strings.dateOfBirth,
                value: _birthDate,
                icon: Icons.cake_outlined,
                onTap: () => _chooseDate(expiry: false),
                onClear: () => setState(() => _birthDate = null),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: InputDecoration(
                  labelText: strings.notes,
                  alignLabelWithHint: true,
                ),
                minLines: 3,
                maxLines: 5,
                inputFormatters: [LengthLimitingTextInputFormatter(2000)],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(strings.saveMember),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: value == null
              ? const Icon(Icons.calendar_month_outlined)
              : IconButton(
                  tooltip: strings.clearDate,
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
        ),
        child: Text(
          value == null
              ? strings.notSpecified
              : DateFormat.yMd(strings.localeName).format(value!),
        ),
      ),
    );
  }
}
