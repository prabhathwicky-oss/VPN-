import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'api.dart';

/// Google Play subscriptions. Every purchase/restore is verified on the
/// server (billing-verify), which is the only place the plan is changed.
class BillingService extends ChangeNotifier {
  BillingService(this._api);
  final Api _api;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool available = false;
  bool busy = false;
  String? message;
  List<ProductDetails> products = [];

  /// Called after the server confirms a purchase so the app can refresh.
  VoidCallback? onEntitlementChanged;

  Future<void> init(Set<String> productIds) async {
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      message = 'Purchase error: $e';
      busy = false;
      notifyListeners();
    });
    try {
      available = await _iap.isAvailable();
    } catch (_) {
      available = false;
    }
    if (!available || productIds.isEmpty) {
      notifyListeners();
      return;
    }
    final resp = await _iap.queryProductDetails(productIds);
    products = List<ProductDetails>.of(resp.productDetails)..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    // Play returns one entry per base plan/offer; keep one per product id.
    final seen = <String>{};
    products = products.where((p) => seen.add(p.id)).toList();
    notifyListeners();
  }

  Future<void> buy(ProductDetails product, String userId) async {
    busy = true;
    message = null;
    notifyListeners();
    try {
      final param = PurchaseParam(productDetails: product, applicationUserName: userId);
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      busy = false;
      message = 'Could not start purchase: $e';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    busy = true;
    message = null;
    notifyListeners();
    try {
      await _iap.restorePurchases();
      // If nothing is restored the stream stays silent; release the spinner.
      Future.delayed(const Duration(seconds: 8), () {
        if (busy) {
          busy = false;
          message ??= 'No active subscription found for this Google account.';
          notifyListeners();
        }
      });
    } catch (e) {
      busy = false;
      message = 'Restore failed: $e';
      notifyListeners();
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.pending:
          busy = true;
          message = 'Payment pending…';
          break;
        case PurchaseStatus.error:
          busy = false;
          message = p.error?.message ?? 'Purchase failed';
          break;
        case PurchaseStatus.canceled:
          busy = false;
          message = null;
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            final res = await _api.verifyPurchase(p.verificationData.serverVerificationData, p.productID);
            message = res['plan'] == 'pro' ? 'Pro is active. Enjoy!' : 'Subscription is not active.';
            onEntitlementChanged?.call();
          } catch (e) {
            message = 'Verification failed: $e';
          }
          busy = false;
          break;
      }
      if (p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p);
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
