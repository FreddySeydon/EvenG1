class PinText {
  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isPinned;

  PinText({
    required this.id,
    required this.content,
    required this.createdAt,
    this.updatedAt,
    this.isPinned = false,
  });

  PinText copyWith({
    String? id,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
  }) {
    return PinText(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'isPinned': isPinned,
  };

  factory PinText.fromJson(Map<String, dynamic> json) => PinText(
    id: json['id'],
    content: json['content'],
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    isPinned: json['isPinned'] ?? false,
  );
}

