import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:p2p_test/models/self_info.dart';
import 'package:p2p_test/providers/self_info_provider.dart';


class PublicAddressCard extends StatelessWidget {
  final VoidCallback? onRefreshTap;

  const PublicAddressCard({super.key, this.onRefreshTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<SelfInfoProvider>(
      builder: (context, provider, _) {
        final isLoading = provider.stunStatus == StunStatus.loading;
        final publicAddr = provider.publicAddress;
        final candidateStr = provider.candidateString;
        final ipLocation = provider.ipLocation;
        final natMeta = provider.natMetadata;
        final publicAddrCopy = publicAddr.isNotEmpty && natMeta != null && natMeta.isNotEmpty
            ? '$publicAddr|$natMeta'
            : publicAddr;

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
                    if (isLoading)
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      InkWell(
                        onTap: onRefreshTap,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.refresh,
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
                  copyText: publicAddrCopy,
                  theme: theme,
                ),
                if (publicAddr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 36),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          ipLocation ?? '查询中...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                _buildNatTypeSection(context, provider, theme),
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

  Widget _buildNatTypeSection(
    BuildContext context,
    SelfInfoProvider provider,
    ThemeData theme,
  ) {
    final selfInfo = provider.selfInfo;
    final natDisplay = selfInfo.natTypeDisplay;

    if (natDisplay.isEmpty) {
      if (selfInfo.stunStatus == StunStatus.loading) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const SizedBox(width: 36),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'NAT 类型探测中...',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final isCone = selfInfo.natType == 'cone';
    final chipColor = isCone
        ? const Color(0xFF2E7D32) // green
        : const Color(0xFFE65100); // deep orange
    final chipBgColor = isCone
        ? const Color(0xFFE8F5E9) // green[50]
        : const Color(0xFFFBE9E7); // deepOrange[50]

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.router_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'NAT 类型',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: chipBgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: chipColor.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: chipColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      selfInfo.natTypeShort,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: chipColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: chipColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isCone ? '易穿透' : '难穿透',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: chipColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isCone
                      ? '各 STUN 服务器返回相同端口映射，NAT 保持一致的端口分配'
                      : '各 STUN 服务器返回不同端口映射，NAT 为每个目标分配不同端口',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: chipColor.withOpacity(0.8),
                  ),
                ),
                if (selfInfo.isSymmetricNat && selfInfo.natPortStep != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '端口递增步长 ≈ ${selfInfo.natPortStep}'
                    '${selfInfo.natPortVelocity != null ? '    漂移速度 ≈ ${selfInfo.natPortVelocity} 端口/秒' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: chipColor.withOpacity(0.8),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow(
    BuildContext context, {
    required String label,
    required String address,
    String? copyText,
    required ThemeData theme,
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
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        if (address.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => _copyAddress(context, copyText ?? address),
            tooltip: '复制公网地址',
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
