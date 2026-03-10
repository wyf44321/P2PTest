import 'package:flutter/material.dart';

import 'package:p2p_test/models/monitored_peer.dart';

class PeerCard extends StatelessWidget {
  final MonitoredPeer peer;

  const PeerCard({super.key, required this.peer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Address
            Text(
              peer.address,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
            if (peer.activeAddress != peer.address &&
                peer.status == ConnectionStatus.connected) ...[
              const SizedBox(height: 2),
              Text(
                '实际连接: ${peer.activeAddress}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
            const SizedBox(height: 4),
            // IP Location
            Text(
              '归属地: ${peer.displayLocation}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            // Status row
            Row(
              children: [
                _buildStatusDot(peer.status),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '状态: ${peer.displayStatus}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _statusColor(peer.status),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Metrics row
            Row(
              children: [
                _buildMetric(
                    context, Icons.timer_outlined, '延迟', peer.displayRtt),
                const SizedBox(width: 24),
                _buildMetric(context, Icons.signal_cellular_alt, '丢包',
                    peer.displayPacketLoss),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDot(ConnectionStatus status) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: _statusColor(status),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildMetric(
      BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Color _statusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connecting:
        return Colors.amber;
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.reconnecting:
        return Colors.orange;
      case ConnectionStatus.disconnected:
        return Colors.red;
      case ConnectionStatus.degradedMonitoring:
        return Colors.grey;
      case ConnectionStatus.failed:
        return Colors.red;
    }
  }
}
