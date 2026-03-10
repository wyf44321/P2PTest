import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:p2p_test/providers/self_info_provider.dart';

class PublicAddressCard extends StatelessWidget {
  final VoidCallback? onSettingsTap;

  const PublicAddressCard({super.key, this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<SelfInfoProvider>(
      builder: (context, provider, _) {
        final publicAddr = provider.publicAddress;
        final localAddr = provider.localAddress;
        final candidateStr = provider.candidateString;
        final ipLocation = provider.ipLocation;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '我的地址',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    InkWell(
                      onTap: onSettingsTap,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.settings,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildAddressRow(
                  context,
                  label: '公网',
                  address: publicAddr,
                  theme: theme,
                  isPrimary: true,
                ),
                if (publicAddr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const SizedBox(width: 36),
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        ipLocation ?? '查询中...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                _buildAddressRow(
                  context,
                  label: '内网',
                  address: localAddr,
                  theme: theme,
                  isPrimary: false,
                ),
                if (candidateStr.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 36,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.share_location,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '候选地址（发给对方）',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              candidateStr,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => _copyAddress(context, candidateStr),
                        tooltip: '复制候选地址',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddressRow(
    BuildContext context, {
    required String label,
    required String address,
    required ThemeData theme,
    required bool isPrimary,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            address.isNotEmpty ? address : '--',
            style: isPrimary
                ? theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.primary,
                  )
                : theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurface,
                  ),
          ),
        ),
        if (address.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => _copyAddress(context, address),
            tooltip: '复制${isPrimary ? "公网" : "内网"}地址',
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  void _copyAddress(BuildContext context, String address) {
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
