import 'package:flutter/material.dart';

import '../../../providers/server_providers.dart';

/// Flips which connected server a browser or destination picker is looking
/// at, without disconnecting anything — [ServerSessionsNotifier] already
/// guarantees switching leaves every session alone.
///
/// Renders nothing when there is nothing to switch between: one connected
/// server does not need a chooser.
class ServerSwitcherChips extends StatelessWidget {
  const ServerSwitcherChips({
    super.key,
    required this.sessions,
    required this.activeServerId,
    required this.onSelect,
  });

  final List<ServerSession> sessions;
  final String activeServerId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (sessions.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: sessions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final session = sessions[index];
          final selected = session.config.id == activeServerId;
          return ChoiceChip(
            label: Text(session.config.name),
            selected: selected,
            onSelected: (_) => onSelect(session.config.id),
          );
        },
      ),
    );
  }
}
