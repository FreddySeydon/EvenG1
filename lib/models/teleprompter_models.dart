class TeleprompterSlide {
  final String id;
  final String text;

  const TeleprompterSlide({
    required this.id,
    required this.text,
  });

  TeleprompterSlide copyWith({
    String? id,
    String? text,
  }) {
    return TeleprompterSlide(
      id: id ?? this.id,
      text: text ?? this.text,
    );
  }

  factory TeleprompterSlide.fromJson(Map<String, dynamic> json) {
    return TeleprompterSlide(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
    };
  }
}

class TeleprompterPresentation {
  final String id;
  final String name;
  final List<TeleprompterSlide> slides;

  const TeleprompterPresentation({
    required this.id,
    required this.name,
    required this.slides,
  });

  TeleprompterPresentation copyWith({
    String? id,
    String? name,
    List<TeleprompterSlide>? slides,
  }) {
    return TeleprompterPresentation(
      id: id ?? this.id,
      name: name ?? this.name,
      slides: slides ?? this.slides,
    );
  }

  factory TeleprompterPresentation.fromJson(Map<String, dynamic> json) {
    final slidesJson = json['slides'] as List<dynamic>? ?? [];
    return TeleprompterPresentation(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      slides: slidesJson
          .map((slide) => TeleprompterSlide.fromJson(
                Map<String, dynamic>.from(slide as Map),
              ))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slides': slides.map((slide) => slide.toJson()).toList(),
    };
  }
}
