import 'package:anteas_rubrica/models/member.dart';
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
    _memberNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _chooseDate({required bool expiry}) async {
    final current = expiry ? _expiryDate : _birthDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: expiry ? DateTime(2100) : DateTime.now(),
      helpText: expiry ? 'SCADENZA TESSERA' : 'DATA DI NASCITA',
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
    if (!_formKey.currentState!.validate()) return;
    if (_firstName.text.trim().isEmpty && _lastName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci almeno il nome o il cognome.')),
      );
      return;
    }
    Navigator.of(context).pop(
      Member(
        id: widget.member?.id,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.trim(),
        memberNumber: _memberNumber.text.trim(),
        expiryDate: _expiryDate,
        birthDate: _birthDate,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.member == null ? 'Nuovo tesserato' : 'Modifica'),
        actions: [TextButton(onPressed: _save, child: const Text('Salva'))],
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
                      decoration: const InputDecoration(labelText: 'Nome'),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [LengthLimitingTextInputFormatter(100)],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastName,
                      decoration: const InputDecoration(labelText: 'Cognome'),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [LengthLimitingTextInputFormatter(100)],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                  labelText: 'Telefono',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _memberNumber,
                decoration: const InputDecoration(
                  labelText: 'Numero tessera',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                inputFormatters: [LengthLimitingTextInputFormatter(100)],
              ),
              const SizedBox(height: 12),
              _DateField(
                label: 'Scadenza tessera',
                value: _expiryDate,
                icon: Icons.event_available_outlined,
                onTap: () => _chooseDate(expiry: true),
                onClear: () => setState(() => _expiryDate = null),
              ),
              const SizedBox(height: 12),
              _DateField(
                label: 'Data di nascita',
                value: _birthDate,
                icon: Icons.cake_outlined,
                onTap: () => _chooseDate(expiry: false),
                onClear: () => setState(() => _birthDate = null),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Note',
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
                label: const Text('Salva tesserato'),
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
                  tooltip: 'Cancella data',
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
        ),
        child: Text(
          value == null
              ? 'Non indicata'
              : DateFormat('dd/MM/yyyy').format(value!),
        ),
      ),
    );
  }
}
