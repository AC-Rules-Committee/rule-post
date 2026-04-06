// flutter_app/lib/core/widgets/team_overview_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rule_post/api/admin_apis.dart'
    show
        adminListAllTeams,
        adminDeleteUser,
        adminToggleUserLock,
        adminDeleteTeam;
import 'package:rule_post/api/user_apis.dart' show sendPasswordResetEmail;

/// A member within a team, as returned by adminListAllTeams.
class _TeamMember {
  final String uid;
  final String email;
  final String displayName;
  final bool teamAdmin;
  final bool disabled;

  _TeamMember({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.teamAdmin,
    required this.disabled,
  });

  factory _TeamMember.fromJson(Map<String, dynamic> json) {
    return _TeamMember(
      uid: json['uid'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      teamAdmin: json['teamAdmin'] as bool? ?? false,
      disabled: json['disabled'] as bool? ?? false,
    );
  }
}

/// Shows all teams with expandable member lists.
/// Site admin can lock/unlock users, delete users, or delete whole teams.
class TeamOverviewPanel extends StatefulWidget {
  const TeamOverviewPanel({super.key});

  @override
  State<TeamOverviewPanel> createState() => _TeamOverviewPanelState();
}

class _TeamOverviewPanelState extends State<TeamOverviewPanel> {
  Map<String, List<_TeamMember>>? _teams;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await adminListAllTeams();
      final teamsRaw = result['teams'] as Map<String, dynamic>? ?? {};
      final teams = <String, List<_TeamMember>>{};
      for (final entry in teamsRaw.entries) {
        final members = (entry.value as List<dynamic>)
            .map(
              (m) => _TeamMember.fromJson(Map<String, dynamic>.from(m as Map)),
            )
            .toList();
        teams[entry.key] = members;
      }
      if (!mounted) return;
      setState(() {
        _teams = teams;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Copy all emails to clipboard ──
  void _copyAllEmails(BuildContext context) {
    final teams = _teams;
    if (teams == null || teams.isEmpty) return;

    final emails =
        teams.values
            .expand((members) => members)
            .map((m) => m.email)
            .where((e) => e.isNotEmpty)
            .toSet() // deduplicate
            .toList()
          ..sort();

    if (emails.isEmpty) return;

    Clipboard.setData(ClipboardData(text: emails.join('; ')));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${emails.length} emails copied to clipboard')),
    );
  }

  // ── Delete user ──
  Future<void> _confirmDeleteUser(_TeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete user'),
        content: Text(
          'Permanently delete ${member.email}?\n\n'
          'This removes them from Auth and Firestore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await adminDeleteUser(context, member.uid);
    } catch (_) {
      /* progress dialog already showed the error */
    }
    if (mounted) await _loadTeams();
  }

  // ── Lock / unlock user ──
  Future<void> _toggleLock(_TeamMember member) async {
    final newState = !member.disabled;
    final action = newState ? 'Lock' : 'Unlock';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('$action user'),
        content: Text(
          '$action ${member.email}?\n\n'
          '${newState ? "They will not be able to sign in." : "They will be able to sign in again."}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await adminToggleUserLock(context, uid: member.uid, disabled: newState);
    } catch (_) {
      /* progress dialog already showed the error */
    }
    if (mounted) await _loadTeams();
  }

  // ── Delete team ──
  Future<void> _confirmDeleteTeam(String team, int memberCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete entire team'),
        content: Text(
          'Permanently delete team $team and all $memberCount member(s)?\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete team'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await adminDeleteTeam(context, team);
    } catch (_) {
      /* progress dialog already showed the error */
    }
    if (mounted) await _loadTeams();
  }

  // ── Send password reset email ──
  Future<void> _confirmResetPassword(_TeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Reset password'),
        content: Text('Send a password reset email to ${member.email}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await sendPasswordResetEmail(context, member.email);
    } catch (_) {
      /* progress dialog already showed the error */
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _teams == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Failed to load teams: $_error'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _loadTeams,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final teams = _teams ?? {};
    if (teams.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No teams found.'),
      );
    }

    // Sort team names alphabetically
    final sortedTeams = teams.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar: Copy all emails + Refresh
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : () => _copyAllEmails(context),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy all emails'),
            ),
            const Spacer(),
            IconButton(
              onPressed: _loading ? null : _loadTeams,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
        ...sortedTeams.map((team) {
          final members = teams[team]!;
          return _TeamTile(
            team: team,
            members: members,
            onDeleteUser: _confirmDeleteUser,
            onToggleLock: _toggleLock,
            onResetPassword: _confirmResetPassword,
            onDeleteTeam: () => _confirmDeleteTeam(team, members.length),
          );
        }),
      ],
    );
  }
}

// ─────────────────── ExpansionTile for one team ───────────────────
class _TeamTile extends StatelessWidget {
  const _TeamTile({
    required this.team,
    required this.members,
    required this.onDeleteUser,
    required this.onToggleLock,
    required this.onResetPassword,
    required this.onDeleteTeam,
  });

  final String team;
  final List<_TeamMember> members;
  final void Function(_TeamMember) onDeleteUser;
  final void Function(_TeamMember) onToggleLock;
  final void Function(_TeamMember) onResetPassword;
  final VoidCallback onDeleteTeam;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Row(
          children: [
            Text(
              team,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Chip(
              label: Text('${members.length}'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (team != 'RC')
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                tooltip: 'Delete entire team',
                onPressed: onDeleteTeam,
              ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: members
            .map(
              (m) => _MemberRow(
                member: m,
                onDelete: () => onDeleteUser(m),
                onToggleLock: () => onToggleLock(m),
                onResetPassword: () => onResetPassword(m),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ─────────────────── Row for one member ───────────────────
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.onDelete,
    required this.onToggleLock,
    required this.onResetPassword,
  });

  final _TeamMember member;
  final VoidCallback onDelete;
  final VoidCallback onToggleLock;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    final name = member.displayName.isNotEmpty
        ? member.displayName
        : _nameFromEmail(member.email);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: member.disabled
            ? Colors.grey.shade400
            : Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          _initials(name),
          style: TextStyle(color: member.disabled ? Colors.white : null),
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(name)),
          if (member.teamAdmin) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Team admin',
              child: Icon(
                Icons.admin_panel_settings,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          if (member.disabled) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Account locked',
              child: Icon(Icons.lock, size: 18, color: Colors.red.shade400),
            ),
          ],
        ],
      ),
      subtitle: Text(member.email),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.lock_reset),
            tooltip: 'Send password reset email',
            onPressed: onResetPassword,
          ),
          IconButton(
            icon: Icon(
              member.disabled ? Icons.lock_open : Icons.lock,
              color: member.disabled ? Colors.green : Colors.orange,
            ),
            tooltip: member.disabled ? 'Unlock user' : 'Lock user',
            onPressed: onToggleLock,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            tooltip: 'Delete user',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  String _nameFromEmail(String email) {
    if (email.isEmpty) return 'Unknown';
    final local = email.split('@')[0];
    final parts = local.split('.');
    if (parts.length > 1) {
      return parts
          .map(
            (p) => p.isNotEmpty
                ? p[0].toUpperCase() + p.substring(1).toLowerCase()
                : '',
          )
          .join(' ');
    }
    return local.isNotEmpty
        ? local[0].toUpperCase() + local.substring(1).toLowerCase()
        : 'Unknown';
  }
}
