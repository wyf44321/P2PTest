import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:p2p_test/config/constants.dart';
import 'package:p2p_test/models/self_info.dart';
import 'package:p2p_test/providers/peer_provider.dart';
import 'package:p2p_test/providers/self_info_provider.dart';
import 'package:p2p_test/widgets/add_peer_dialog.dart';
import 'package:p2p_test/widgets/peer_card.dart';
import 'package:p2p_test/widgets/public_address_card.dart';
import 'package:p2p_test/widgets/stun_loading_view.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SelfInfoProvider>(
      builder: (context, selfInfo, _) {
        if (selfInfo.stunStatus == StunStatus.loading &&
            selfInfo.selfInfo.publicIp == null) {
          return const StunLoadingView();
        }
        return _MainContent();
      },
    );
  }
}

class _MainContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // App header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.link,
                        size: 28,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppConstants.appName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppConstants.appSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Public address card
            PublicAddressCard(
              onRefreshTap: () {
                context.read<SelfInfoProvider>().refresh();
              },
            ),

            const SizedBox(height: 8),

            // Section header: "监听用户" + "清除断开" + "+" buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '监听用户',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // Clear disconnected button
                  Consumer<PeerProvider>(
                    builder: (context, provider, _) {
                      final enabled = provider.hasDisconnectedPeers;
                      return TextButton.icon(
                        onPressed: enabled
                            ? () => _showClearConfirmDialog(context)
                            : null,
                        icon: Icon(
                          Icons.clear_all,
                          size: 18,
                          color: enabled
                              ? theme.colorScheme.error
                              : theme.disabledColor,
                        ),
                        label: Text(
                          '清除断开',
                          style: TextStyle(
                            fontSize: 13,
                            color: enabled
                                ? theme.colorScheme.error
                                : theme.disabledColor,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  // Add button
                  IconButton(
                    icon: Icon(
                      Icons.add_circle,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: () => _showAddPeerDialog(context),
                    visualDensity: VisualDensity.compact,
                    tooltip: '添加监听用户',
                  ),
                ],
              ),
            ),

            const Divider(indent: 16, endIndent: 16, height: 1),

            // Peer list
            Expanded(
              child: Consumer<PeerProvider>(
                builder: (context, provider, _) {
                  if (provider.peers.isEmpty) {
                    return _buildEmptyState(context);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 16),
                    itemCount: provider.peers.length,
                    itemBuilder: (context, index) {
                      final peer = provider.peers[index];
                      return Dismissible(
                        key: Key(peer.id),
                        direction: DismissDirection.endToStart,
                        background: _buildDeleteBackground(),
                        confirmDismiss: (_) async => true,
                        onDismissed: (_) {
                          provider.removePeer(peer.id);
                        },
                        child: PeerCard(peer: peer),
                      );
                    },
                  );
                },
              ),
            ),

            // Version footer
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                AppConstants.appVersion,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无监听用户，点击＋添加',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete, color: Colors.white),
          SizedBox(height: 2),
          Text(
            '删除',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showAddPeerDialog(BuildContext context) async {
    final peerProvider = context.read<PeerProvider>();

    if (!context.mounted) return;

    final result = await showDialog<AddPeerResult>(
      context: context,
      builder: (ctx) => AddPeerDialog(
        peerExists: peerProvider.peerExists,
      ),
    );

    if (result != null) {
      peerProvider.addPeer(result.parsed);
    }
  }

  void _showClearConfirmDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定清除所有已断开和连接失败的监听用户？'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      context.read<PeerProvider>().clearDisconnectedPeers();
    }
  }
}
