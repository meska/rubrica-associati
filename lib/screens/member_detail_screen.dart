import 'package:anteas_rubrica/data/member_repository.dart';
import 'package:anteas_rubrica/models/member.dart';
import 'package:anteas_rubrica/screens/member_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({
    super.key,
    required this.member,
    required this.repository,
  });

  final Member member;
  final MemberRepository repository;

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  late Member _member;

  @override
  void initState() {
    super.initState();
    _member = widget.member;
  }

  Future<void> _call() async {
    if (_member.phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: _member.phone);
    if (await launchUrl(uri)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Non è stato possibile aprire il telefono.'),
      ),
    );
  }

  Future<void> _edit() async {
    final edited = await Navigator.of(context).push<Member>(
      MaterialPageRoute(builder: (_) => MemberFormScreen(member: _member)),
    );
    if (edited == null) return;
    final saved = await widget.repository.save(edited);
    if (!mounted) return;
    setState(() {
      _member = saved;
    });
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare il tesserato?'),
        content: Text('${_member.fullName} verrà rimosso dalla rubrica.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true || _member.id == null) return;
    await widget.repository.delete(_member.id!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tesserato'),
        actions: [
          IconButton(
            tooltip: 'Modifica',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _delete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Elimina'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CircleAvatar(
            radius: 42,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              _member.initials,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _member.fullName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          if (_member.phone.isNotEmpty)
            FilledButton.icon(
              onPressed: _call,
              icon: const Icon(Icons.call),
              label: Text('Chiama ${_member.phone}'),
            ),
          const SizedBox(height: 18),
          Card(
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.phone_outlined,
                  label: 'Telefono',
                  value: _member.phone,
                ),
                _DetailRow(
                  icon: Icons.badge_outlined,
                  label: 'Numero tessera',
                  value: _member.memberNumber,
                ),
                _DetailRow(
                  icon: Icons.event_available_outlined,
                  label: 'Scadenza tessera',
                  value: _formatDate(_member.expiryDate),
                  warning: _member.isExpired,
                ),
                _DetailRow(
                  icon: Icons.cake_outlined,
                  label: 'Data di nascita',
                  value: _formatDate(_member.birthDate),
                ),
                _DetailRow(
                  icon: Icons.notes_outlined,
                  label: 'Note',
                  value: _member.notes,
                  last: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) =>
      value == null ? '' : DateFormat('dd/MM/yyyy').format(value);
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.warning = false,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool warning;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final shownValue = value.isEmpty ? 'Non indicato' : value;
    final color = warning ? Theme.of(context).colorScheme.error : null;
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: color),
          title: Text(label),
          subtitle: Text(shownValue, style: TextStyle(color: color)),
          trailing: warning ? const Chip(label: Text('Scaduta')) : null,
        ),
        if (!last) const Divider(height: 1, indent: 56),
      ],
    );
  }
}
