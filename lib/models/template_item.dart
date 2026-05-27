import '../utils/json_utils.dart';

class TemplateItem {
  final String id;
  final String templateId;
  final int position;
  final String title;
  final String? description;
  final bool isRequired;

  const TemplateItem({
    required this.id,
    required this.templateId,
    required this.position,
    required this.title,
    this.description,
    this.isRequired = true,
  });

  factory TemplateItem.fromJson(Map<String, dynamic> json) {
    return TemplateItem(
      id: json['id'] as String,
      templateId: json['template_id'] as String,
      position: (json['position'] as num).toInt(),
      title: json['title'] as String,
      description: json['description'] as String?,
      isRequired: jsonBool(json['is_required'], fallback: true),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'is_required': isRequired,
      };
}
