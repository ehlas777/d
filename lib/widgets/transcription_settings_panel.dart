import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/transcription_options.dart';

class TranscriptionSettingsPanel extends StatefulWidget {
  final TranscriptionOptions options;
  final Function(TranscriptionOptions) onOptionsChanged;

  const TranscriptionSettingsPanel({
    super.key,
    required this.options,
    required this.onOptionsChanged,
  });

  @override
  State<TranscriptionSettingsPanel> createState() =>
      _TranscriptionSettingsPanelState();
}

class _TranscriptionSettingsPanelState
    extends State<TranscriptionSettingsPanel> {
  late TranscriptionOptions _options;

  @override
  void initState() {
    super.initState();
    _options = widget.options;
  }

  void _updateOptions(TranscriptionOptions newOptions) {
    setState(() {
      _options = newOptions;
    });
    widget.onOptionsChanged(newOptions);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('transcription_settings'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 18,
              ),
        ),
        const SizedBox(height: 24),

        // Model Selection
        _buildSection(
          icon: Icons.model_training,
          title: l10n.translate('model'),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                _buildModelToggle(
                  context,
                  l10n.translate('fast'), // 'base' model
                  'base',
                ),
                const SizedBox(width: 8),
                _buildModelToggle(
                  context,
                  l10n.translate('accurate'), // 'small' model
                  'small',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Language Detection
        _buildSection(
          icon: Icons.language,
          title: l10n.translate('language_detection'),
          child: Column(
            children: [
              RadioListTile<String?>(
                title: Text(l10n.translate('auto_detect')),
                value: null,
                groupValue: _options.language,
                onChanged: (value) {
                  _updateOptions(_options.copyWith(language: value));
                },
              ),
              RadioListTile<String?>(
                title: Text(l10n.translate('kazakh')),
                value: 'kk',
                groupValue: _options.language,
                onChanged: (value) {
                  _updateOptions(_options.copyWith(language: value));
                },
              ),
              RadioListTile<String?>(
                title: Text(l10n.translate('russian')),
                value: 'ru',
                groupValue: _options.language,
                onChanged: (value) {
                  _updateOptions(_options.copyWith(language: value));
                },
              ),
              RadioListTile<String?>(
                title: Text(l10n.translate('english')),
                value: 'en',
                groupValue: _options.language,
                onChanged: (value) {
                  _updateOptions(_options.copyWith(language: value));
                },
              ),
              RadioListTile<String?>(
                title: Text(l10n.translate('chinese')),
                value: 'zh',
                groupValue: _options.language,
                onChanged: (value) {
                  _updateOptions(_options.copyWith(language: value));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Options toggles
        _buildSection(
          icon: Icons.settings,
          title: l10n.settings,
          child: Column(
            children: [
              _buildSwitchTile(
                icon: Icons.access_time,
                title: l10n.translate('timestamps'),
                value: _options.timestamps,
                onChanged: (value) {
                  _updateOptions(_options.copyWith(timestamps: value));
                },
              ),
              _buildSwitchTile(
                icon: Icons.record_voice_over,
                title: l10n.translate('speaker_diarization'),
                value: _options.speakerDiarization,
                onChanged: (value) {
                  _updateOptions(_options.copyWith(speakerDiarization: value));
                },
              ),
              _buildSwitchTile(
                icon: Icons.block,
                title: l10n.translate('profanity_filter'),
                value: _options.profanityFilter,
                onChanged: (value) {
                  _updateOptions(_options.copyWith(profanityFilter: value));
                },
              ),
              _buildSwitchTile(
                icon: Icons.text_format,
                title: l10n.translate('punctuation'),
                value: _options.punctuation,
                onChanged: (value) {
                  _updateOptions(_options.copyWith(punctuation: value));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.accentColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, size: 20, color: AppTheme.textSecondary),
      title: Text(title),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.accentColor,
      ),
    );
  }

  Widget _buildModelToggle(
      BuildContext context, String label, String modelName) {
    final isSelected = _options.model == modelName;
    return Expanded(
      child: GestureDetector(
        onTap: () => _updateOptions(_options.copyWith(model: modelName)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accentColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8.0),
            border: isSelected
                ? null
                : Border.all(color: AppTheme.borderColor),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
