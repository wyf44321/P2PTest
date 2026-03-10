import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:p2p_test/utils/validators.dart';

class AddPeerResult {
  final String ip;
  final int port;

  AddPeerResult(this.ip, this.port);
}

class AddPeerDialog extends StatefulWidget {
  final bool Function(String ip, int port) peerExists;
  final String? initialIp;
  final int? initialPort;

  const AddPeerDialog({
    super.key,
    required this.peerExists,
    this.initialIp,
    this.initialPort,
  });

  @override
  State<AddPeerDialog> createState() => _AddPeerDialogState();
}

class _AddPeerDialogState extends State<AddPeerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  String? _duplicateError;
  bool _clipboardValid = false;
  String? _clipboardIp;
  int? _clipboardPort;

  @override
  void initState() {
    super.initState();
    if (widget.initialIp != null) {
      _ipController.text = widget.initialIp!;
    }
    if (widget.initialPort != null) {
      _portController.text = widget.initialPort.toString();
    }
    _checkClipboard();
  }

  Future<void> _checkClipboard() async {
    try {
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final parsed = clipData?.text != null
          ? Validators.parseIpPort(clipData!.text!)
          : null;
      if (mounted) {
        setState(() {
          _clipboardValid = parsed != null;
          _clipboardIp = parsed?.ip;
          _clipboardPort = parsed?.port;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _clipboardValid = false);
      }
    }
  }

  void _autoFillFromClipboard() {
    if (_clipboardIp != null && _clipboardPort != null) {
      setState(() {
        _ipController.text = _clipboardIp!;
        _portController.text = _clipboardPort.toString();
        _duplicateError = null;
      });
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('添加监听用户'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_clipboardValid)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: _autoFillFromClipboard,
                  icon: const Icon(Icons.paste, size: 18),
                  label: Text('自动填入 $_clipboardIp:$_clipboardPort'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(color: theme.colorScheme.primary),
                    minimumSize: const Size(double.infinity, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            TextFormField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'IP 地址',
                hintText: '例: 203.0.113.42',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.computer),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              validator: Validators.validateIp,
              onChanged: (_) {
                if (_duplicateError != null) {
                  setState(() => _duplicateError = null);
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: '端口',
                hintText: '例: 12345',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              validator: Validators.validatePort,
              onChanged: (_) {
                if (_duplicateError != null) {
                  setState(() => _duplicateError = null);
                }
              },
            ),
            if (_duplicateError != null) ...[
              const SizedBox(height: 8),
              Text(
                _duplicateError!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _onAdd,
          child: const Text('添加'),
        ),
      ],
    );
  }

  void _onAdd() {
    if (!_formKey.currentState!.validate()) return;

    final ip = _ipController.text.trim();
    final port = int.parse(_portController.text.trim());

    if (widget.peerExists(ip, port)) {
      setState(() {
        _duplicateError = '该用户已在监听列表中';
      });
      return;
    }

    Navigator.of(context).pop(AddPeerResult(ip, port));
  }
}
