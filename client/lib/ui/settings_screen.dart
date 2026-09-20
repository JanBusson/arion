import 'package:flutter/material.dart';

import '../configuration/settings_controller.dart';
import '../library/offline_library.dart';

final class OfflineLibrarySettings extends StatelessWidget {
  const OfflineLibrarySettings({required this.controller, super.key});

  final OfflineLibraryController controller;

  Future<void> _setEnabled(BuildContext context, bool value) async {
    if (value) {
      await controller.enable();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove offline library?'),
        content: const Text(
          'Downloaded songs and the offline catalog will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-disable-offline'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove downloads'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.disable();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('keep-library-offline'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Keep library offline'),
          subtitle: const Text(
            'Automatically downloads every song using the current connection and private app storage.',
          ),
          value: controller.isEnabled,
          onChanged: (value) => _setEnabled(context, value),
        ),
        if (controller.isEnabled) ...[
          Text(_offlineStatus(controller)),
          if (controller.phase == OfflineLibraryPhase.failed ||
              controller.phase == OfflineLibraryPhase.unavailable)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('retry-offline-sync'),
                onPressed: controller.retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry downloads'),
              ),
            ),
        ],
      ],
    ),
  );
}

String _offlineStatus(
  OfflineLibraryController controller,
) => switch (controller.phase) {
  OfflineLibraryPhase.disabled => 'Offline downloads are disabled.',
  OfflineLibraryPhase.preparing =>
    'Preparing ${controller.completedCount}/${controller.totalCount}'
        '${controller.activeCount > 0 ? ' (${controller.activeCount} active)' : ''}',
  OfflineLibraryPhase.ready =>
    'Ready offline: ${controller.completedCount}/${controller.totalCount}',
  OfflineLibraryPhase.unavailable =>
    'Server unavailable. ${controller.completedCount}/${controller.totalCount} saved.',
  OfflineLibraryPhase.failed =>
    '${controller.error ?? 'Download failed.'} ${controller.completedCount}/${controller.totalCount} saved.',
};

final class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.settings,
    required this.onSave,
    super.key,
  });

  final SettingsController settings;
  final Future<bool> Function(String value) onSave;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to Arion')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Private server',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter the HTTP or HTTPS address of your private Arion API. No requests are sent until it is saved.',
                    ),
                    const SizedBox(height: 20),
                    ServerSettingsForm(
                      settings: settings,
                      initialValue: settings.baseUrl?.toString() ?? '',
                      onSave: onSave,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class ServerSettingsForm extends StatefulWidget {
  const ServerSettingsForm({
    required this.settings,
    required this.initialValue,
    required this.onSave,
    this.onSaved,
    super.key,
  });

  final SettingsController settings;
  final String initialValue;
  final Future<bool> Function(String value) onSave;
  final VoidCallback? onSaved;

  @override
  State<ServerSettingsForm> createState() => _ServerSettingsFormState();
}

final class _ServerSettingsFormState extends State<ServerSettingsForm> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  Future<void> _submit() async {
    final saved = await widget.onSave(_controller.text);
    if (saved && mounted) {
      widget.onSaved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('server-url-field'),
            controller: _controller,
            enabled: !widget.settings.isSaving,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'API base URL',
              hintText: 'http://192.168.1.50:8000',
              errorText: widget.settings.error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('save-server-button'),
            onPressed: widget.settings.isSaving ? null : _submit,
            icon: widget.settings.isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Save server'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
