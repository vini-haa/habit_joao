class Habit {
  final int id;
  final String name;
  final String? description;
  final String countMethod;
  final String completionMethod;
  final int? targetQuantity;
  final int? targetDaysPerWeek;
  final String createdAt;
  final bool isCompletedToday;
  final String? lastCompletedDate;
  final int? currentPeriodQuantity;
  final int? currentPeriodDaysCompleted;

  Habit({
    required this.id,
    required this.name,
    this.description,
    required this.countMethod,
    required this.completionMethod,
    this.targetQuantity,
    this.targetDaysPerWeek,
    required this.createdAt,
    required this.isCompletedToday,
    this.lastCompletedDate,
    this.currentPeriodQuantity,
    this.currentPeriodDaysCompleted,
  });

  // Construtor de fábrica para criar uma instância de Habit a partir de um mapa JSON
  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      countMethod: json['count_method'],
      completionMethod: json['completion_method'],
      targetQuantity: json['target_quantity'],
      targetDaysPerWeek: json['target_days_per_week'],
      createdAt: json['created_at'],
      isCompletedToday: json['is_completed_today'],
      lastCompletedDate: json['last_completed_date'],
      currentPeriodQuantity: json['current_period_quantity'],
      currentPeriodDaysCompleted: json['current_period_days_completed'],
    );
  }
}
