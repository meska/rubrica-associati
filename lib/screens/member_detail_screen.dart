import 'package:rubrica_associati/data/member_repository.dart';
import 'package:rubrica_associati/data/register_repository.dart';
import 'package:rubrica_associati/l10n/generated/app_localizations.dart';
import 'package:rubrica_associati/models/member.dart';
import 'package:rubrica_associati/screens/member_form_screen.dart';
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
  List<RegisterEvent> _history = const [];

  @override
  void initState() {
    super.initState();
    _member = widget.member;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final id = _member.id;
    if (id == null) return;
    final history = await widget.repository.registerHistory(id);
    if (!mounted) return;
    setState(() => _history = history);
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await launchUrl(uri)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).phoneOpenFailed)),
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
    await _loadHistory();
  }

  Future<void> _delete() async {
    final strings = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteMemberQuestion),
        content: Text(strings.memberWillBeRemoved(_member.fullName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.delete),
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
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.member),
        actions: [
          IconButton(
            tooltip: strings.edit,
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _delete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(strings.delete),
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
              onPressed: () => _call(_member.phone),
              icon: const Icon(Icons.call),
              label: Text(strings.callPhone(_member.phone)),
            ),
          if (_member.secondaryPhone.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _call(_member.secondaryPhone),
              icon: const Icon(Icons.call_outlined),
              label: Text(strings.callPhone(_member.secondaryPhone)),
            ),
          ],
          const SizedBox(height: 18),
          Card(
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.phone_outlined,
                  label: strings.phone,
                  value: _member.phone,
                ),
                _DetailRow(
                  icon: Icons.phone_outlined,
                  label: strings.secondaryPhone,
                  value: _member.secondaryPhone,
                ),
                _DetailRow(
                  icon: Icons.badge_outlined,
                  label: strings.memberNumber,
                  value: _member.memberNumber,
                ),
                _DetailRow(
                  icon: Icons.event_available_outlined,
                  label: strings.membershipExpiry,
                  value: _formatDate(_member.expiryDate, strings.localeName),
                  warning: _member.isExpired,
                ),
                _DetailRow(
                  icon: Icons.cake_outlined,
                  label: strings.dateOfBirth,
                  value: _formatDate(_member.birthDate, strings.localeName),
                ),
                _DetailRow(
                  icon: Icons.notes_outlined,
                  label: strings.notes,
                  value: _member.notes,
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            strings.registerHistoryTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                if (_history.isEmpty)
                  ListTile(title: Text(strings.registerHistoryEmpty))
                else
                  for (final e in _history)
                    ListTile(
                      key: ValueKey('register-event-${e.id}'),
                      leading: const Icon(Icons.history),
                      title: Text(_eventLabel(strings, e.type)),
                      subtitle: Text(
                        _formatIso(e.eventDate, strings.localeName),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _eventLabel(AppLocalizations strings, RegisterEventType type) =>
      switch (type) {
        RegisterEventType.admission => strings.registerEventAdmission,
        RegisterEventType.cessation => strings.registerEventCessation,
        RegisterEventType.correction => strings.registerEventCorrection,
      };

  String _formatIso(String iso, String localeName) {
    final parsed = DateTime.tryParse(iso);
    return parsed == null ? iso : DateFormat.yMd(localeName).format(parsed);
  }

  String _formatDate(DateTime? value, String localeName) =>
      value == null ? '' : DateFormat.yMd(localeName).format(value);
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
    final strings = AppLocalizations.of(context);
    final shownValue = value.isEmpty ? strings.notProvided : value;
    final color = warning ? Theme.of(context).colorScheme.error : null;
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: color),
          title: Text(label),
          subtitle: Text(shownValue, style: TextStyle(color: color)),
          trailing: warning ? Chip(label: Text(strings.expired)) : null,
        ),
        if (!last) const Divider(height: 1, indent: 56),
      ],
    );
  }
}
