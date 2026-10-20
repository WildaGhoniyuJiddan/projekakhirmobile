import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:worthbang/models/chat_models.dart';
import 'package:worthbang/services/api_exception.dart';

final chatApiProvider = Provider<ChatApi>((ref) => ChatApi());

/// API chatbot Bang Worth — lewat Edge Function Supabase `bang-worth`.
///
/// Gemini dipanggil server-side di fungsi itu; API key tidak pernah
/// masuk APK dan fungsi menolak request tanpa JWT user yang login.
class ChatApi {
  Future<ChatReply> ask(
    String message, {
    List<ChatMessage> history = const [],
  }) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'bang-worth',
        body: {
          'message': message,
          'history': history.map((m) => m.toJson()).toList(),
        },
      );
      final data = res.data;
      if (data is Map<String, dynamic>) return ChatReply.fromJson(data);
      if (data is Map) {
        return ChatReply.fromJson(Map<String, dynamic>.from(data));
      }
      throw const ApiException('Respons Bang Worth tidak valid.');
    } on FunctionException catch (e) {
      throw ApiException(_functionErrorMessage(e), e.status);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw const ApiException(
        'Tidak dapat terhubung ke Bang Worth. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  /// Pesan error dari Edge Function berbentuk {"error": "..."}.
  String _functionErrorMessage(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    if (e.status == 401) return 'Sesi berakhir. Silakan login lagi.';
    return 'Bang Worth sedang bermasalah. Coba lagi nanti.';
  }
}
