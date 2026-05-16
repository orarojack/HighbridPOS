// lib/features/home_shell.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_controller.dart';
import 'auth/lock_screen.dart';
import 'pos/sale_screen.dart';
import 'products/product_list_screen.dart';
import 'reports/daily_summary_screen.dart';
import 'returns/returns_lookup_screen.dart';
import 'shift/shift_screen.dart';

/// Idle time after which the terminal auto-locks.
const _autoLockTimeout = Duration(minutes: 5);

/// Main navigation shell shown to a logged-in user.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  /// Whether the lock screen is currently overlaying the shell. Local UI
  /// state only — locking never logs the user out.
  bool _locked = false;

  /// Idle auto-lock timer; restarted on every user interaction.
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _restartIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  /// Cancels and restarts the idle timer so auto-lock fires [_autoLockTimeout]
  /// after the last interaction.
  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_autoLockTimeout, _lock);
  }

  void _lock() {
    _idleTimer?.cancel();
    if (mounted && !_locked) setState(() => _locked = true);
  }

  void _unlock() {
    if (!mounted) return;
    setState(() => _locked = false);
    _restartIdleTimer();
  }

  /// Resets the idle timer on any user interaction while unlocked.
  void _onInteraction([dynamic _]) {
    if (!_locked) _restartIdleTimer();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    if (user == null) return const SizedBox.shrink();

    final destinations = <({IconData icon, String label, Widget page})>[
      (icon: Icons.point_of_sale, label: 'Sell', page: const SaleScreen()),
      (
        icon: Icons.assignment_return,
        label: 'Returns',
        page: const ReturnsLookupScreen()
      ),
      (icon: Icons.schedule, label: 'Shift', page: const ShiftScreen()),
      if (user.role.canManageProducts)
        (
          icon: Icons.inventory_2,
          label: 'Products',
          page: const ProductListScreen()
        ),
      (
        icon: Icons.summarize,
        label: 'Daily Summary',
        page: const DailySummaryScreen()
      ),
    ];
    final safeIndex = _index.clamp(0, destinations.length - 1);

    return Scaffold(
      body: Stack(
        children: [
          Listener(
            onPointerDown: _onInteraction,
            onPointerSignal: _onInteraction,
            child: Row(
              children: [
                NavigationRail(
                  extended: true,
                  selectedIndex: safeIndex,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  leading: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('HighbridPOS',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(user.fullName,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton.icon(
                              onPressed: _lock,
                              icon: const Icon(Icons.lock_outline),
                              label: const Text('Lock'),
                            ),
                            TextButton.icon(
                              onPressed: () => ref
                                  .read(authControllerProvider.notifier)
                                  .logout(),
                              icon: const Icon(Icons.logout),
                              label: const Text('Log out'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: destinations[safeIndex].page),
              ],
            ),
          ),
          if (_locked)
            Positioned.fill(
              child: LockScreen(onUnlocked: _unlock),
            ),
        ],
      ),
    );
  }
}
