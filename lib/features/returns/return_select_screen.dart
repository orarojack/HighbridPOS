// lib/features/returns/return_select_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/return_repository.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../../shared/manager_approval.dart';
import '../../shared/money.dart';
import '../auth/auth_controller.dart';
import '../shift/shift_controller.dart';
import 'return_controller.dart';
import 'return_receipt.dart';

/// Step 2 of the returns flow: pick the lines and quantities to return from
/// the looked-up sale, give a reason, and record the return / cash refund.
class ReturnSelectScreen extends ConsumerStatefulWidget {
  const ReturnSelectScreen({super.key});

  @override
  ConsumerState<ReturnSelectScreen> createState() =>
      _ReturnSelectScreenState();
}

class _ReturnSelectScreenState extends ConsumerState<ReturnSelectScreen> {
  final _reason = TextEditingController();
  bool _recording = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _record(ReturnDraft draft) async {
    // A return refunds cash from the drawer; it requires an open shift.
    final shift = ref.read(shiftControllerProvider).valueOrNull;
    if (shift == null) {
      _snack('Open a shift before recording a return / cash refund.');
      return;
    }

    final approver = await requestManagerApproval(
      context,
      ref,
      action: 'Record return / cash refund',
    );
    if (approver == null) return; // Cancelled — nothing is recorded.

    final cashier = ref.read(authControllerProvider)!;
    setState(() => _recording = true);
    try {
      final record =
          await ref.read(returnRepositoryProvider).recordReturn(
                originalSaleId: draft.originalSaleId,
                cashierId: cashier.id,
                shiftId: shift.id,
                reason: draft.reason,
                approvedBy: approver.id,
                selectedLines: draft.lines,
              );
      // Keep the shift's running cash total current after the refund.
      await ref.read(shiftControllerProvider.notifier).refresh();
      if (!mounted) return;
      setState(() => _recording = false);
      await showReturnReceiptDialog(context, record);
      if (mounted) Navigator.of(context).pop();
    } on OverReturnException catch (e) {
      if (mounted) {
        setState(() => _recording = false);
        _snack('Return failed: $e');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _recording = false);
        _snack('Return failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(returnControllerProvider);

    return state.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Return')),
        body: Center(child: Text('Could not load the sale: $e')),
      ),
      data: (draft) => draft == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Return')),
              body: const Center(child: Text('No sale selected.')),
            )
          : _buildSelectUi(context, draft),
    );
  }

  Widget _buildSelectUi(BuildContext context, ReturnDraft draft) {
    final controller = ref.read(returnControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('Return — sale ${draft.originalReference}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Choose what to return',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final line in draft.lines)
                  _ReturnLineTile(
                    line: line,
                    onChanged: (qty) =>
                        controller.setLineQty(line.saleItemId, qty),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason for return',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: controller.setReason,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Refund total',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        formatMoney(draft.refundTotal),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    icon: _recording
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                        : const Icon(Icons.assignment_turned_in),
                    label: const Text('Record return'),
                    onPressed: (!draft.hasSelection || _recording)
                        ? null
                        : () => _record(draft),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One sale line in the return-selection list: shows sold / returnable
/// quantities and a quantity stepper capped at [ReturnLineDraft.returnableQty].
/// Fully-returned lines are shown disabled.
class _ReturnLineTile extends StatelessWidget {
  const _ReturnLineTile({required this.line, required this.onChanged});

  final ReturnLineDraft line;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final fullyReturned = line.returnableQty == 0;
    final canDecrement = !fullyReturned && line.selectedQty > 0;
    final canIncrement =
        !fullyReturned && line.selectedQty < line.returnableQty;

    return Card(
      child: Opacity(
        opacity: fullyReturned ? 0.5 : 1.0,
        child: ListTile(
          title: Text(line.nameSnapshot),
          subtitle: Text(
            fullyReturned
                ? 'Sold ${line.soldQty} · fully returned'
                : 'Sold ${line.soldQty} · returnable ${line.returnableQty} · '
                    '${formatMoney(line.unitPrice)} each',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: canDecrement
                    ? () => onChanged(line.selectedQty - 1)
                    : null,
              ),
              SizedBox(
                width: 28,
                child: Text('${line.selectedQty}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: canIncrement
                    ? () => onChanged(line.selectedQty + 1)
                    : null,
              ),
              SizedBox(
                width: 84,
                child: Text(formatMoney(line.lineTotal),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
