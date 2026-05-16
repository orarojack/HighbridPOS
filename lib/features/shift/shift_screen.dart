// lib/features/shift/shift_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import 'end_shift_screen.dart';
import 'shift_controller.dart';
import 'shift_summary.dart';
import 'start_shift_screen.dart';

/// Rail destination for shift management: shows the start-shift screen when
/// no shift is open, the end-shift screen for the user's open shift, and the
/// summary of the shift just closed (until a new one is started).
class ShiftScreen extends ConsumerStatefulWidget {
  const ShiftScreen({super.key});

  @override
  ConsumerState<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends ConsumerState<ShiftScreen> {
  /// Summary of the shift just closed on this screen; cleared once a fresh
  /// shift opens so the start-screen takes over.
  ShiftSummary? _closedSummary;

  @override
  Widget build(BuildContext context) {
    final shiftState = ref.watch(shiftControllerProvider);
    return shiftState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Could not load the shift: $e')),
      ),
      data: (shift) {
        if (shift != null) {
          return EndShiftScreen(
            shift: shift,
            onClosed: (summary) =>
                setState(() => _closedSummary = summary),
          );
        }
        final summary = _closedSummary;
        if (summary != null) {
          return Scaffold(
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShiftSummaryView(summary: summary),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start a new shift'),
                        onPressed: () =>
                            setState(() => _closedSummary = null),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return const StartShiftScreen();
      },
    );
  }
}
