import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../models/models.dart';

/// Thin client for the YPN edge functions.
class Api {
  SupabaseClient get _db => Supabase.instance.client;

  Future<Map<String, dynamic>> _call(String fn, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 20)}) async {
    try {
      final res = await _db.functions.invoke(fn, body: body).timeout(timeout);
      final data = res.data;
      if (data is Map) return data.cast<String, dynamic>();
      return <String, dynamic>{};
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is Map) {
        final err = (details['error'] as Map).cast<String, dynamic>();
        throw ApiException('${err['code']}', '${err['message']}', e.status);
      }
      throw ApiException('http_${e.status}', 'Server error (${e.status}). Please try again.', e.status);
    } on TimeoutException {
      throw ApiException('network', 'The server is not responding. Check your connection.');
    } on SocketException {
      throw ApiException('network', 'No internet connection.');
    } on AuthException catch (e) {
      throw ApiException('auth', e.message);
    } catch (e) {
      final s = '$e';
      if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup')) {
        throw ApiException('network', 'No internet connection.');
      }
      rethrow;
    }
  }

  Future<void> ensureSession() async {
    if (_db.auth.currentSession != null) return;
    try {
      await _db.auth.signInAnonymously().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('network', 'The server is not responding. Check your connection.');
    } on AuthException catch (e) {
      throw ApiException('auth', e.message);
    } on SocketException {
      throw ApiException('network', 'No internet connection.');
    }
  }

  Future<Bootstrap> bootstrap(String installId) async {
    await ensureSession();
    final j = await _call('app-bootstrap', {
      'install_id': installId,
      'model': Platform.operatingSystemVersion,
      'app_version': Env.appVersion,
    });
    return Bootstrap.fromJson(j);
  }

  Future<Map<String, dynamic>> connect({
    required String installId,
    required String region,
    required String protocol,
    String? wgPublicKey,
    List<String> excludeNodes = const [],
  }) async {
    await ensureSession();
    return _call('vpn-connect', {
      'install_id': installId,
      'region': region,
      'protocol': protocol,
      if (wgPublicKey != null) 'wg_public_key': wgPublicKey,
      'exclude_nodes': excludeNodes,
    }, timeout: const Duration(seconds: 25));
  }

  Future<void> disconnect(String installId) async {
    try {
      await _call('vpn-disconnect', {'install_id': installId}, timeout: const Duration(seconds: 6));
    } catch (_) {
      // best effort — the server recycles idle sessions on its own
    }
  }

  Future<Map<String, dynamic>> verifyPurchase(String token, String productId) =>
      _call('billing-verify', {'purchase_token': token, 'product_id': productId});

  // ------------------------------------------------------------- account
  Future<void> sendEmailCode(String email, {required bool link}) async {
    try {
      if (link) {
        await _db.auth.updateUser(UserAttributes(email: email));
      } else {
        await _db.auth.signInWithOtp(email: email, shouldCreateUser: true);
      }
    } on AuthException catch (e) {
      throw ApiException('auth', e.message);
    }
  }

  Future<void> verifyEmailCode(String email, String code, {required bool link}) async {
    try {
      await _db.auth.verifyOTP(
        email: email,
        token: code,
        type: link ? OtpType.emailChange : OtpType.email,
      );
    } on AuthException catch (e) {
      throw ApiException('auth', e.message);
    }
  }

  Future<void> signOut() async {
    try {
      await _db.auth.signOut();
    } catch (_) {}
  }
}
