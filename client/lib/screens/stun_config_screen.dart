import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:p2p_test/config/constants.dart';
import 'package:p2p_test/config/stun_servers.dart';
import 'package:p2p_test/models/self_info.dart';
import 'package:p2p_test/providers/self_info_provider.dart';
import 'package:p2p_test/utils/validators.dart';

class StunConfigScreen extends StatefulWidget {
  final bool isFromFailure;

  const StunConfigScreen({super.key, this.isFromFailure = false});

  @override
  State<StunConfigScreen> createState() => _StunConfigScreenState();
}

class _StunConfigScreenState extends State<StunConfigScreen> {
  String? _selectedServer = StunServers.initialDefault.address;
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  bool _isCustom = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // App header
            Icon(
              Icons.link,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              AppConstants.appName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppConstants.appSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Warning banner
            if (widget.isFromFailure)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: theme.colorScheme.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'STUN 服务不可用，请选择或输入 STUN 服务器',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (_errorMessage != null)
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Server list section
                  Text(
                    '可选服务器',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: StunServers.defaultServers
                          .map((server) => RadioListTile<String>(
                                title: Text(
                                  server.name,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                subtitle: Text(
                                  server.address,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                value: server.address,
                                groupValue:
                                    _isCustom ? null : _selectedServer,
                                onChanged: (v) {
                                  setState(() {
                                    _selectedServer = v;
                                    _isCustom = false;
                                    _errorMessage = null;
                                  });
                                },
                                dense: true,
                              ))
                          .toList(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Custom input section
                  Text(
                    '自定义服务器',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _hostController,
                            decoration: const InputDecoration(
                              labelText: '服务器地址',
                              hintText: '例: stun.example.com',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) {
                              setState(() {
                                _isCustom = true;
                                _selectedServer = null;
                                _errorMessage = null;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _portController,
                            decoration: const InputDecoration(
                              labelText: '端口',
                              hintText: '例: 3478',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(5),
                            ],
                            onChanged: (_) {
                              setState(() {
                                _isCustom = true;
                                _selectedServer = null;
                                _errorMessage = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (!widget.isFromFailure) ...[
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _isLoading
                              ? null
                              : () => context
                                  .read<SelfInfoProvider>()
                                  .cancelConfiguring(),
                          child:
                              const Text('返回', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _onRetry,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('重新获取',
                                style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onRetry() async {
    String? server;

    if (_isCustom) {
      final host = _hostController.text.trim();
      final portStr = _portController.text.trim();
      final hostError = Validators.validateStunAddress(host);
      final portError = Validators.validateStunPort(portStr);

      if (hostError != null || portError != null) {
        setState(() {
          _errorMessage = '请输入合法的服务器地址（host:port）';
        });
        return;
      }
      server = '$host:$portStr';
    } else {
      server = _selectedServer;
    }

    if (server == null || server.isEmpty) {
      setState(() {
        _errorMessage = '请选择或输入一个 STUN 服务器';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final provider = context.read<SelfInfoProvider>();
    await provider.retryWithServer(server, _isCustom);

    if (mounted) {
      if (provider.stunStatus == StunStatus.success) {
        // Success - the HomeScreen will auto-switch
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = '获取失败，请尝试其他服务器';
        });
      }
    }
  }
}
