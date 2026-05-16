// lib/features/home_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_controller.dart';
import 'pos/sale_screen.dart';
import 'products/product_list_screen.dart';
import 'reports/daily_summary_screen.dart';

/// Main navigation shell shown to a logged-in user.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    if (user == null) return const SizedBox.shrink();

    final destinations = <({IconData icon, String label, Widget page})>[
      (icon: Icons.point_of_sale, label: 'Sell', page: const SaleScreen()),
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
      body: Row(
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
                  child: TextButton.icon(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
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
    );
  }
}
