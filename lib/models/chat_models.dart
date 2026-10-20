/// Model chatbot Bang Worth (kontrak: B7 POST /api/v1/chat/ask).
class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  /// role: 'user' | 'assistant'
  final String role;
  final String text;

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}

class BuildItem {
  const BuildItem({
    required this.component,
    required this.name,
    required this.price,
  });

  final String component;
  final String name;
  final int price;

  factory BuildItem.fromJson(Map<String, dynamic> json) => BuildItem(
        component: json['component'] as String? ?? '',
        name: json['name'] as String? ?? '',
        price: (json['price'] as num?)?.toInt() ?? 0,
      );
}

class BuildCardData {
  const BuildCardData({
    required this.items,
    required this.total,
    this.note,
  });

  final List<BuildItem> items;
  final int total;
  final String? note;

  factory BuildCardData.fromJson(Map<String, dynamic> json) =>
      BuildCardData(
        items: ((json['items'] as List?) ?? [])
            .map((e) => BuildItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (json['total'] as num?)?.toInt() ?? 0,
        note: json['note'] as String?,
      );
}

class ChatReply {
  const ChatReply({required this.reply, this.build});

  final String reply;
  final BuildCardData? build;

  factory ChatReply.fromJson(Map<String, dynamic> json) => ChatReply(
        reply: json['reply'] as String? ?? '',
        build: json['build'] == null
            ? null
            : BuildCardData.fromJson(
                json['build'] as Map<String, dynamic>),
      );
}
