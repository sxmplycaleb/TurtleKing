import 'package:flutter/material.dart';

import 'onboarding_store.dart';

/// A simple step indicator for the onboarding flow.
///
/// Shows four labeled dots connected by lines. The current step is
/// highlighted; completed steps are filled; future steps are unfilled.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({super.key, required this.currentStep});

  final OnboardingStep currentStep;

  static const _labels = ['Age', 'Confirm', 'Drinking', 'Terms'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = OnboardingStep.values;
    final currentIndex = steps.indexOf(currentStep);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  color: i <= currentIndex
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
            _StepDot(
              label: _labels[i],
              isCompleted: i < currentIndex,
              isCurrent: i == currentIndex,
              stepIndex: i,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.isCompleted,
    required this.isCurrent,
    required this.stepIndex,
  });

  final String label;
  final bool isCompleted;
  final bool isCurrent;
  final int stepIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isCurrent
        ? theme.colorScheme.primary
        : isCompleted
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted || isCurrent ? color : Colors.transparent,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: isCompleted
                ? Icon(Icons.check, size: 16, color: theme.colorScheme.surface)
                : Text(
                    '${isCurrent ? stepIndex + 1 : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isCurrent
                          ? theme.colorScheme.surface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isCurrent
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
