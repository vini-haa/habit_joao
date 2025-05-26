import 'category_model.dart'; // Importe o novo modelo

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
  final int currentStreak;
  final List<CategoryModel> categories; // Alterado de String? category para List<CategoryModel>

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
    required this.currentStreak,
    this.categories = const [], // Default para lista vazia
  });

  factory Habit.fromJson(Map<String, dynamic> json) {
    List<CategoryModel> parsedCategories = [];
    if (json['categories'] != null && json['categories'] is List) {
      parsedCategories = (json['categories'] as List)
          .map((catJson) => CategoryModel.fromJson(catJson as Map<String, dynamic>))
          .toList();
    }

    return Habit(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      countMethod: json['count_method'] as String,
      completionMethod: json['completion_method'] as String,
      targetQuantity: int.tryParse(json['target_quantity']?.toString() ?? ''),
      targetDaysPerWeek: int.tryParse(json['target_days_per_week']?.toString() ?? ''),
      createdAt: json['created_at'] as String,
      isCompletedToday: json['is_completed_today'] as bool,
      lastCompletedDate: json['last_completed_date'] as String?,
      currentPeriodQuantity: int.tryParse(json['current_period_quantity']?.toString() ?? ''),
      currentPeriodDaysCompleted: int.tryParse(json['current_period_days_completed']?.toString() ?? ''),
      currentStreak: json['current_streak'] as int,
      categories: parsedCategories,
    );
  }
}
