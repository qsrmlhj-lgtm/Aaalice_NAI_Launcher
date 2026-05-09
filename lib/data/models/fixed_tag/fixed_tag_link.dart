import 'package:uuid/uuid.dart';

/// 固定词联动关系。
///
/// 方向固定为 positive -> negative。联动只影响 UI toggle 同步，
/// prompt 拼接阶段仍只读取各条目的 enabled 状态。
class FixedTagLink {
  const FixedTagLink({
    required this.id,
    required this.positiveEntryId,
    required this.negativeEntryId,
  });

  factory FixedTagLink.create({
    required String positiveEntryId,
    required String negativeEntryId,
  }) {
    return FixedTagLink(
      id: const Uuid().v4(),
      positiveEntryId: positiveEntryId,
      negativeEntryId: negativeEntryId,
    );
  }

  factory FixedTagLink.fromJson(Map<String, dynamic> json) {
    return FixedTagLink(
      id: json['id'] as String? ?? const Uuid().v4(),
      positiveEntryId: json['positiveEntryId'] as String? ?? '',
      negativeEntryId: json['negativeEntryId'] as String? ?? '',
    );
  }

  final String id;
  final String positiveEntryId;
  final String negativeEntryId;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'positiveEntryId': positiveEntryId,
      'negativeEntryId': negativeEntryId,
    };
  }

  FixedTagLink copyWith({
    String? id,
    String? positiveEntryId,
    String? negativeEntryId,
  }) {
    return FixedTagLink(
      id: id ?? this.id,
      positiveEntryId: positiveEntryId ?? this.positiveEntryId,
      negativeEntryId: negativeEntryId ?? this.negativeEntryId,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FixedTagLink &&
            other.id == id &&
            other.positiveEntryId == positiveEntryId &&
            other.negativeEntryId == negativeEntryId;
  }

  @override
  int get hashCode => Object.hash(id, positiveEntryId, negativeEntryId);
}
