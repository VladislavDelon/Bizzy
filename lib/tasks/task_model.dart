/// Личная задача/дело мастера или клиента.
class TaskItem {
  const TaskItem({
    this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.dueAt,
    this.notifyMinutes = 0,
    this.isDone = false,
    required this.createdAt,
  });

  final int? id;
  final int userId;
  final String title;
  final String description;
  final DateTime dueAt;
  final int notifyMinutes;
  final bool isDone;
  final DateTime createdAt;

  TaskItem copyWith({
    int? id,
    int? userId,
    String? title,
    String? description,
    DateTime? dueAt,
    int? notifyMinutes,
    bool? isDone,
    DateTime? createdAt,
  }) =>
      TaskItem(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        title: title ?? this.title,
        description: description ?? this.description,
        dueAt: dueAt ?? this.dueAt,
        notifyMinutes: notifyMinutes ?? this.notifyMinutes,
        isDone: isDone ?? this.isDone,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'userId': userId,
        'title': title,
        'description': description,
        'dueAt': dueAt.toIso8601String(),
        'notifyMinutes': notifyMinutes,
        'isDone': isDone ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TaskItem.fromMap(Map<String, Object?> map) => TaskItem(
        id: map['id'] as int?,
        userId: map['userId'] as int,
        title: map['title'] as String,
        description: map['description'] as String,
        dueAt: DateTime.parse(map['dueAt'] as String),
        notifyMinutes: map['notifyMinutes'] as int? ?? 0,
        isDone: (map['isDone'] as int? ?? 0) == 1,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
