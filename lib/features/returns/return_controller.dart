// lib/features/returns/return_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/return_repository.dart';
import '../../domain/models.dart';
import '../../providers.dart';

/// Holds the in-memory [ReturnDraft] being assembled before persistence.
///
/// State is an [AsyncValue]:
/// - [AsyncLoading] while [loadSale] is resolving.
/// - [AsyncData]`(null)` when no return is in progress.
/// - [AsyncData]`(draft)` when a draft is loaded and being edited.
/// - [AsyncError] when [loadSale] fails unexpectedly.
class ReturnController extends StateNotifier<AsyncValue<ReturnDraft?>> {
  ReturnController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  ReturnRepository get _repo => _ref.read(returnRepositoryProvider);

  /// Looks up [referenceNo] and loads a fresh [ReturnDraft] (all selectedQty
  /// 0). Sets state to [AsyncData]`(null)` when the sale is not found, and
  /// [AsyncError] on unexpected failures.
  Future<void> loadSale(String referenceNo) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.findSaleForReturn(referenceNo));
  }

  /// Updates the [selectedQty] for the line with [saleItemId].
  ///
  /// [qty] is clamped to `[0, line.returnableQty]`. No-ops if no draft is
  /// loaded or the line is not found.
  void setLineQty(int saleItemId, int qty) {
    final draft = state.valueOrNull;
    if (draft == null) return;

    final idx = draft.lines.indexWhere((l) => l.saleItemId == saleItemId);
    if (idx == -1) return;

    final line = draft.lines[idx];
    final clamped = qty.clamp(0, line.returnableQty);

    final newLines = [
      for (var i = 0; i < draft.lines.length; i++)
        if (i == idx) line.copyWith(selectedQty: clamped) else draft.lines[i],
    ];

    state = AsyncValue.data(ReturnDraft(
      originalSaleId: draft.originalSaleId,
      originalReference: draft.originalReference,
      lines: newLines,
      reason: draft.reason,
    ));
  }

  /// Updates the [reason] text on the current draft. No-ops if no draft is
  /// loaded.
  void setReason(String reason) {
    final draft = state.valueOrNull;
    if (draft == null) return;

    state = AsyncValue.data(ReturnDraft(
      originalSaleId: draft.originalSaleId,
      originalReference: draft.originalReference,
      lines: draft.lines,
      reason: reason,
    ));
  }

  /// Discards the current draft and returns to the idle state.
  void clear() => state = const AsyncValue.data(null);
}

/// Exposes the [ReturnController] and its [AsyncValue]`<ReturnDraft?>` state.
final returnControllerProvider =
    StateNotifierProvider<ReturnController, AsyncValue<ReturnDraft?>>(
  (ref) => ReturnController(ref),
);
