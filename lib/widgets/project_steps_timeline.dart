import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/translation_project.dart';

class ProjectStepsTimeline extends StatelessWidget {
  final TranslationProject? project;
  final void Function(ProjectStep)? onStepTap;
  final bool isCollapsed;

  const ProjectStepsTimeline({
    super.key,
    this.project,
    this.onStepTap,
    this.isCollapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: EdgeInsets.all(isCollapsed ? 12 : 16),
      child: Column(
        crossAxisAlignment:
            isCollapsed ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          if (!isCollapsed) ...[
            Text(
              l10n.translate('project_steps'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
          ],
          _buildStepItem(
            context,
            step: ProjectStep.transcription,
            icon: Icons.transcribe,
            label: l10n.translate('step_transcription'),
            isCollapsed: isCollapsed,
          ),
          _buildStepItem(
            context,
            step: ProjectStep.translation,
            icon: Icons.translate,
            label: l10n.translate('step_translation'),
            isCollapsed: isCollapsed,
          ),
          _buildStepItem(
            context,
            step: ProjectStep.tts,
            icon: Icons.volume_up,
            label: l10n.translate('step_tts'),
            isCollapsed: isCollapsed,
          ),
          _buildStepItem(
            context,
            step: ProjectStep.merge,
            icon: Icons.merge_type,
            label: l10n.translate('step_merge'),
            isLast: true,
            isCollapsed: isCollapsed,
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(
    BuildContext context, {
    required ProjectStep step,
    required IconData icon,
    required String label,
    bool isLast = false,
    bool isCollapsed = false,
  }) {
    final stepProgress = project?.steps[step];
    final isCompleted = stepProgress?.status == ProjectStatus.completed;
    final isInProgress = stepProgress?.status == ProjectStatus.inProgress;
    final isCurrent = project?.currentStep == step;

    // Determine colors
    final Color iconColor;
    final Color textColor;
    final Color backgroundColor;

    if (isCompleted) {
      iconColor = AppTheme.successColor;
      textColor = AppTheme.successColor;
      backgroundColor = AppTheme.successColor.withValues(alpha: 0.1);
    } else if (isInProgress || isCurrent) {
      iconColor = AppTheme.accentColor;
      textColor = AppTheme.textPrimary;
      backgroundColor = AppTheme.accentColor.withValues(alpha: 0.1);
    } else {
      iconColor = Colors.grey;
      textColor = Colors.grey;
      backgroundColor = Colors.grey.withValues(alpha: 0.1);
    }

    // Қадамды басуға болатындай ету
    final canTap = (isCompleted || isInProgress) && !isCurrent;

    Widget content;
    if (isCollapsed) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted ? Icons.check_circle : icon,
              color: iconColor,
              size: 22,
            ),
          ),
          if (isInProgress && stepProgress?.progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: 40,
                child: LinearProgressIndicator(
                  value: stepProgress!.progress,
                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  color: AppTheme.accentColor,
                  minHeight: 4,
                ),
              ),
            ),
        ],
      );
    } else {
      content = Row(
        children: [
          // Step indicator circle
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted ? Icons.check_circle : icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          // Step label
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: textColor,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                ),
                if (isInProgress && stepProgress?.progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      value: stepProgress!.progress,
                      backgroundColor: Colors.grey.withValues(alpha: 0.2),
                      color: AppTheme.accentColor,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    final item = InkWell(
      onTap: canTap && onStepTap != null ? () => onStepTap!(step) : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: isCollapsed ? 6 : 4,
          horizontal: isCollapsed ? 0 : 8,
        ),
        child: content,
      ),
    );

    return Column(
      children: [
        Tooltip(
          message: label,
          waitDuration: const Duration(milliseconds: 400),
          child: item,
        ),
        if (!isLast)
          Padding(
            padding: EdgeInsets.only(
              left: isCollapsed ? 0 : 19,
              top: 4,
              bottom: 4,
            ),
            child: Container(
              width: 2,
              height: isCollapsed ? 28 : 24,
              color: isCompleted ? AppTheme.successColor : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }
}
