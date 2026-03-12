class Note {
  final String id;
  final String title;
  final String body;
  final String folderId;
  final List<String> tagIds;
  final List<String> imagePaths;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;
  final bool isDeleted;

  const Note({
    required this.id,
    this.title = '',
    this.body = '',
    this.folderId = '',
    this.tagIds = const [],
    this.imagePaths = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.isDeleted = false,
  });

  Note copyWith({
    String? id,
    String? title,
    String? body,
    String? folderId,
    List<String>? tagIds,
    List<String>? imagePaths,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    bool? isDeleted,
  }) =>
      Note(
        id: id ?? this.id,
        title: title ?? this.title,
        body: body ?? this.body,
        folderId: folderId ?? this.folderId,
        tagIds: tagIds ?? this.tagIds,
        imagePaths: imagePaths ?? this.imagePaths,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isPinned: isPinned ?? this.isPinned,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        folderId: (m['folder_id'] as String?) ?? '',
        tagIds: _splitList(m['tag_ids']),
        imagePaths: _splitList(m['image_paths']),
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
        isPinned: (m['is_pinned'] as int?) == 1,
        isDeleted: (m['is_deleted'] as int?) == 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'folder_id': folderId,
        'tag_ids': tagIds.join(','),
        'image_paths': imagePaths.join(','),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'is_pinned': isPinned ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
      };

  static List<String> _splitList(dynamic v) {
    if (v == null || v == '') return [];
    return (v as String).split(',');
  }
}
