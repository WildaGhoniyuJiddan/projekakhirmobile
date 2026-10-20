/// Exception saat kalkulasi rakit PC (misal budget terlalu kecil).
class BuilderException implements Exception {
  const BuilderException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BuildComponent {
  const BuildComponent({required this.name, required this.price});

  final String name;
  final int price;

  factory BuildComponent.fromJson(Map<String, dynamic> json) =>
      BuildComponent(
        name: json['name'] as String? ?? '-',
        price: (json['price'] as num?)?.toInt() ?? 0,
      );
}

class RandomBuild {
  const RandomBuild({
    required this.cpu,
    required this.gpu,
    required this.ram,
    required this.ssd,
    required this.psu,
    required this.total,
    required this.budget,
  });

  final BuildComponent cpu;
  final BuildComponent gpu;
  final BuildComponent ram;
  final BuildComponent ssd;
  final BuildComponent psu;
  final int total;
  final int budget;

  factory RandomBuild.fromJson(Map<String, dynamic> json) => RandomBuild(
        cpu: BuildComponent.fromJson(
            json['cpu'] as Map<String, dynamic>? ?? {}),
        gpu: BuildComponent.fromJson(
            json['gpu'] as Map<String, dynamic>? ?? {}),
        ram: BuildComponent.fromJson(
            json['ram'] as Map<String, dynamic>? ?? {}),
        ssd: BuildComponent.fromJson(
            json['ssd'] as Map<String, dynamic>? ?? {}),
        psu: BuildComponent.fromJson(
            json['psu'] as Map<String, dynamic>? ?? {}),
        total: (json['total'] as num?)?.toInt() ?? 0,
        budget: (json['budget'] as num?)?.toInt() ?? 0,
      );

  List<(String, BuildComponent)> get parts => [
        ('CPU', cpu),
        ('GPU', gpu),
        ('RAM', ram),
        ('SSD', ssd),
        ('PSU', psu),
      ];
}
