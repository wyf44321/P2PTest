import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:p2p_test/utils/validators.dart';

class AddPeerResult {
  final ParsedCandidateInput parsed;

  AddPeerResult(this.parsed);
}

class AddPeerDialog extends StatefulWidget {
  final bool Function(ParsedCandidateInput input) peerExists;
  final String? initialValue;

  const AddPeerDialog({
    super.key,
    required this.peerExists,
    this.initialValue,
  });

  @override
  State<AddPeerDialog> createState() => _AddPeerDialogState();
}

class _AddPeerDialogState extends State<AddPeerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  String? _duplicateError;
  bool _clipboardValid = false;
  String? _clipboardValue;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    _checkClipboard();
  }

  Future<void> _checkClipboard() async {
    try {
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipData?.text == null) return;
      final text = clipData!.text!.trim();
      final parsed = Validators.parseCandidateInput(text);
      if (mounted && parsed != null) {
        setState(() {
          _clipboardValid = true;
          _clipboardValue = text;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _clipboardValid = false);
      }
    }
  }

  void _autoFillFromClipboard() {
    if (_clipboardValue != null) {
      setState(() {
        _controller.text = _clipboardValue!;
        _duplicateError = null;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
                  label: Text(
                    '粘贴剪切板地址',
                    overflow: TextOverflow.ellipsis,
                  ),
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
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '对方地址',
                hintText: '例: 1.2.3.4:50001 或 [2001:db8::1]:50001',
                helperText: '支持 IPv4/IPv6，粘贴对方候选地址即可',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.computer),
              ),
              keyboardType: TextInputType.text,
              maxLines: 2,
              minLines: 1,
              validator: Validators.validateCandidateString,
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

    final parsed = Validators.parseCandidateInput(_controller.text)!;

    if (widget.peerExists(parsed)) {
      setState(() {
        _duplicateError = '该用户已在监听列表中';
      });
      return;
    }

    Navigator.of(context).pop(AddPeerResult(parsed));
  }
}
