class Folder {
  final String id;
  final String name;
  final int sortOrder;

  const Folder({required this.id, required this.name, this.sortOrder = 0});

  factory Folder.fromMap(Map<String, dynamic> m) => Folder(
        id: m['id'] as String,
        name: m['name'] as String,
        sortOrder: (m['sort_order'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'sort_order': sortOrder,
      };
}
