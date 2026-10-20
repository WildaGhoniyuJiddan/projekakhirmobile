/// Model toko (lokal, dari dataset CSV toko yang dibundel).
class Store {
  const Store({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distanceKm,
    required this.prices,
  });

  final int id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double distanceKm;
  final Map<String, int> prices;

  factory Store.fromJson(Map<String, dynamic> json) {
    final pricesJson =
        (json['prices'] as Map?)?.cast<String, dynamic>() ?? {};
    return Store(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '-',
      address: json['address'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      prices: pricesJson.map((k, v) => MapEntry(k, (v as num).toInt())),
    );
  }

  /// Harga produk [query] di toko ini (cocok sebagian, case-insensitive).
  int? priceFor(String query) {
    final q = query.toLowerCase();
    for (final e in prices.entries) {
      if (e.key.toLowerCase().contains(q) || q.contains(e.key.toLowerCase())) {
        return e.value;
      }
    }
    return null;
  }
}
