// frontend/lib/models/habit_record.dart
class HabitRecord {
  final DateTime recordDate;
  final int? quantityCompleted; // Pode ser null para métodos 'boolean'

  HabitRecord({required this.recordDate, this.quantityCompleted});

  factory HabitRecord.fromJson(Map<String, dynamic> json) {
    return HabitRecord(
      recordDate: DateTime.parse(json['record_date'] as String),
      quantityCompleted: json['quantity_completed'] as int?,
    );
  }
}
