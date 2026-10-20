import 'package:intl/intl.dart';

/// Format integer IDR ke Rupiah Indonesia, mis. 4500000 → "Rp4.500.000".
///
/// Harga di API selalu integer IDR (API_CONTRACT.md), jadi input bertipe int.
String formatRupiah(int amount) {
  final formatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );
  return formatter.format(amount);
}
