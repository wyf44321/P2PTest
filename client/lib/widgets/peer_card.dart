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
            // IP Location - separate row, two lines max
            Text(
              '归属地: ${peer.displayLocation}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (peer.natMetadata != null) ...[
              const SizedBox(height: 2),
              Text(
                'NAT: ${peer.natMetadata}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ],
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
            if (peer.status == ConnectionStatus.connected) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  _buildStatChip(
                    context,
                    '延迟',
                    peer.latencyDisplay,
                    _latencyColor(peer.latencyMs),
                  ),
                  const SizedBox(width: 12),
                  _buildStatChip(
                    context,
                    '丢包',
                    peer.lossDisplay,
                    _lossColor(peer.packetLossPercent),
                  ),
                ],
              ),
            ],
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
      case ConnectionStatus.failed:
        return Colors.red;
    }
  }

  Widget _buildStatChip(
      BuildContext context, String label, String value, Color color) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
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
            color: color,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Color _latencyColor(double? ms) {
    if (ms == null) return Colors.grey;
    if (ms < 100) return Colors.green;
    if (ms < 300) return Colors.amber;
    return Colors.red;
  }

  Color _lossColor(double? percent) {
    if (percent == null) return Colors.grey;
    if (percent < 1) return Colors.green;
    if (percent < 5) return Colors.amber;
    return Colors.red;
  }
}
