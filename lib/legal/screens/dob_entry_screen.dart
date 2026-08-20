import 'package:flutter/material.dart';

import '../age_calculator.dart';
import '../onboarding_store.dart';

/// Screen 1 of the onboarding flow: Date of Birth selection.
///
/// Uses a native Material date picker. Future dates are rejected.
/// The calculated age is displayed once a valid DOB is chosen.
class DobEntryScreen extends StatefulWidget {
  const DobEntryScreen({
    super.key,
    required this.store,
    this.minimumAge = AgeCalculator.defaultMinimumAge,
  });

  final OnboardingStore store;

  /// The minimum age required to proceed.
  final int minimumAge;

  @override
  State<DobEntryScreen> createState() => _DobEntryScreenState();
}

class _DobEntryScreenState extends State<DobEntryScreen> {
  DateTime? _selectedDob;
  int? _calculatedAge;
  bool _showUnderageBlock = false;

  @override
  void initState() {
    super.initState();
    // No prefilled DOB — the user must explicitly select one.
    // Sync with the store's underage state (e.g. if navigating back).
    _showUnderageBlock = widget.store.underageBlocked;
  }

  void _recalculateAge() {
    final age = AgeCalculator.calculateAge(_selectedDob);
    setState(() {
      _calculatedAge = age;
      if (age != null && age < widget.minimumAge) {
        _showUnderageBlock = true;
      } else {
        _showUnderageBlock = false;
      }
    });
  }

  void _syncStore() {
    if (_calculatedAge != null && _calculatedAge! < widget.minimumAge) {
      widget.store.setUnderageBlocked(true);
    } else {
      widget.store.setUnderageBlocked(false);
      if (_calculatedAge != null) {
        widget.store.setDobSelected(true);
      }
    }
  }

  Future<void> _pickDate() async {
    final maxDate = AgeCalculator.maxEligibleDate(
      minimumAge: widget.minimumAge,
    );
    // When no DOB is selected, default the picker view to the max eligible
    // date so the user sees the most recent selectable dates first.
    final initial = _selectedDob ?? maxDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(maxDate) ? maxDate : initial,
      firstDate: DateTime(1900),
      lastDate: maxDate,
      helpText: 'SELECT DATE OF BIRTH',
      cancelText: 'Cancel',
      confirmText: 'OK',
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
      });
      _recalculateAge();
      _syncStore();
    }
  }

  void _onContinue() {
    if (_calculatedAge == null || _calculatedAge! < widget.minimumAge) return;
    widget.store.advanceStep();
  }

  String _formatDate(DateTime date) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Branding
                    Center(
                      child: Image.asset(
                        'assets/branding/turtle_king_emblem.png',
                        width: 80,
                        height: 80,
                        fit: BoxFit.contain,
                        semanticLabel: 'Turtle King logo',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Before You Play',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'TurtleKing is intended for adults only.\nPlease enter your date of birth to continue.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // DOB display and picker button
                    Text(
                      'Date of Birth',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          _selectedDob != null
                              ? _formatDate(_selectedDob!)
                              : 'Select your date of birth',
                          style: theme.textTheme.titleMedium,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Age display
                    if (_calculatedAge != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _calculatedAge! >= widget.minimumAge
                                  ? Icons.check_circle_outline
                                  : Icons.cancel_outlined,
                              color: _calculatedAge! >= widget.minimumAge
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Your age: $_calculatedAge years',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Underage block message
                    if (_showUnderageBlock) ...[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sorry, You Can\'t Play Yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'TurtleKing is a drinking game intended for adults '
                              'aged ${widget.minimumAge} and over. Because you '
                              'are under ${widget.minimumAge}, you cannot access '
                              'or play the game.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This restriction helps keep alcohol-related '
                              'gameplay away from people who are not legally '
                              'old enough to participate.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Action button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: _showUnderageBlock
                    ? OutlinedButton(
                        onPressed: () {
                          // Allow the user to go back and correct the DOB.
                          setState(() {
                            _showUnderageBlock = false;
                          });
                          widget.store.setUnderageBlocked(false);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 16,
                          ),
                          textStyle: theme.textTheme.titleMedium,
                        ),
                        child: const Text('Back'),
                      )
                    : FilledButton(
                        onPressed:
                            (_calculatedAge != null &&
                                _calculatedAge! >= widget.minimumAge)
                            ? _onContinue
                            : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 16,
                          ),
                          textStyle: theme.textTheme.titleMedium,
                        ),
                        child: const Text('Continue'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
