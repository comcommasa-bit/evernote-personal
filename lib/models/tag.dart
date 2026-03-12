class Tag {
  final String id;
  final String name;

  const Tag({required this.id, required this.name});

  factory Tag.fromMap(Map<String, dynamic> m) => Tag(
        id: m['id'] as String,
        name: m['name'] as String,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
      };
}
