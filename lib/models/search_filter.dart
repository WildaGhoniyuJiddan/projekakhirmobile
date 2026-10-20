import 'package:worthbang/models/price_check_models.dart';

/// Opsi urutan hasil pencarian.
enum SortOption { priceAsc, priceDesc, similarity }

/// Filter & sort hasil pembanding (diterapkan lokal di atas [PriceComparison]).
class SearchFilter {
  const SearchFilter({
    this.conditions = const {},
    this.sources = const {},
    this.maxPrice,
    this.sort = SortOption.priceAsc,
  });

  /// Kondisi yang diizinkan; kosong = semua.
  final Set<String> conditions;
  final Set<String> sources;
  final int? maxPrice;
  final SortOption sort;

  SearchFilter copyWith({
    Set<String>? conditions,
    Set<String>? sources,
    int? Function()? maxPrice,
    SortOption? sort,
  }) => SearchFilter(
    conditions: conditions ?? this.conditions,
    sources: sources ?? this.sources,
    maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
    sort: sort ?? this.sort,
  );

  /// Terapkan filter + sort ke daftar pembanding.
  List<PriceComparison> apply(List<PriceComparison> input) {
    var out = input.where((c) {
      final condition = switch (c.condition) {
        'new' => 'baru',
        'second' => 'bekas',
        _ => c.condition,
      };
      if (conditions.isNotEmpty &&
          (condition == null || !conditions.contains(condition))) {
        return false;
      }
      if (sources.isNotEmpty && !sources.contains(c.source)) return false;
      if (maxPrice != null && c.price > maxPrice!) return false;
      return true;
    }).toList();
    switch (sort) {
      case SortOption.priceAsc:
        out.sort((a, b) => a.price.compareTo(b.price));
      case SortOption.priceDesc:
        out.sort((a, b) => b.price.compareTo(a.price));
      case SortOption.similarity:
        out.sort((a, b) => (b.similarity ?? 0).compareTo(a.similarity ?? 0));
    }
    return out;
  }
}
