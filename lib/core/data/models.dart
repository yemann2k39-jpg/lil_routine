/// Domain models for the LilRoutine data layer.
library;

/// Local date key used for grouping entries by day: yyyy-MM-dd.
String dateKey(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

enum EntryType { water, food }

enum MealType { breakfast, lunch, dinner, snack }

/// Smart default meal type from the current time.
/// 05-11: breakfast · 11-15: lunch · 15-21: dinner · otherwise: snack
/// (late-night eating counts as snack).
MealType guessMealType(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 11) return MealType.breakfast;
  if (h >= 11 && h < 15) return MealType.lunch;
  if (h >= 15 && h < 21) return MealType.dinner;
  return MealType.snack;
}

/// Time-of-day greeting for the water page header.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return 'Good morning';
  if (h >= 12 && h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// A drink quick-slot on the water page: tap to log [ml] instantly.
/// Max 4 slots; the 4th tap target on the page is the "+ add cup" square.
class DrinkSlot {
  const DrinkSlot({
    this.id,
    required this.name,
    required this.ml,
    this.position = 0,
  });

  final int? id;
  final String name;
  final int ml;
  final int position;

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'ml': ml,
      'position': position,
    };
  }

  static DrinkSlot fromMap(Map<String, Object?> map) {
    return DrinkSlot(
      id: map['id'] as int?,
      name: map['name'] as String,
      ml: map['ml'] as int,
      position: map['position'] as int? ?? 0,
    );
  }
}

enum HabitKind { waterGoal, underKcalGoal, noLateEating, manual }

/// Portion-scaled macro sums for one day (grams). Meals dashboard stats.
class MacroTotals {
  const MacroTotals({
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
  });

  final double protein;
  final double carbs;
  final double fat;

  static MacroTotals zero() => const MacroTotals();
}

/// Portion-scaled sodium (mg) + sugar (g) sums for one day — used by
/// insight rules and the AI coach recap only; never rendered as goals.
class MicroTotals {
  const MicroTotals({this.sodiumMg = 0, this.sugarG = 0});

  final double sodiumMg;
  final double sugarG;

  static MicroTotals zero() => const MicroTotals();
}

/// One row of the unified daily log: either a water amount or a food item.
class Entry {
  const Entry({
    this.id,
    required this.type,
    this.amountMl,
    this.name,
    this.mealType,
    this.kcal,
    this.protein,
    this.carbs,
    this.fat,
    this.fiber,
    this.sugar,
    this.sodium,
    this.portion = 1,
    required this.createdAt,
    required this.date,
  });

  final int? id;
  final EntryType type;
  final int? amountMl; // water only
  final String? name; // food only
  final MealType? mealType; // food only
  final double? kcal; // food only, per 1x portion
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? fiber; // food only, grams
  final double? sugar; // food only, grams
  final double? sodium; // food only, milligrams
  final double portion; // multiplier applied at log time
  final DateTime createdAt;
  final String date;

  bool get isWater => type == EntryType.water;

  /// Calories actually logged (kcal scaled by portion).
  double? get effectiveKcal =>
      kcal == null ? null : (kcal! * portion);

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'type': type.name,
      'amount_ml': amountMl,
      'name': name,
      'meal_type': mealType?.name,
      'kcal': kcal,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'fiber': fiber,
      'sugar': sugar,
      'sodium': sodium,
      'portion': portion,
      'created_at': createdAt.millisecondsSinceEpoch,
      'date': date,
    };
  }

  static Entry fromMap(Map<String, Object?> map) {
    return Entry(
      id: map['id'] as int?,
      type: EntryType.values.byName(map['type'] as String),
      amountMl: map['amount_ml'] as int?,
      name: map['name'] as String?,
      mealType: map['meal_type'] == null
          ? null
          : MealType.values.byName(map['meal_type'] as String),
      kcal: (map['kcal'] as num?)?.toDouble(),
      protein: (map['protein'] as num?)?.toDouble(),
      carbs: (map['carbs'] as num?)?.toDouble(),
      fat: (map['fat'] as num?)?.toDouble(),
      fiber: (map['fiber'] as num?)?.toDouble(),
      sugar: (map['sugar'] as num?)?.toDouble(),
      sodium: (map['sodium'] as num?)?.toDouble(),
      portion: (map['portion'] as num?)?.toDouble() ?? 1,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      date: map['date'] as String,
    );
  }
}

/// A personal food in the user's own database (recents + favorites).
class FoodItem {
  const FoodItem({
    this.id,
    required this.name,
    this.kcal = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.sugar = 0,
    this.sodium = 0,
    this.isFavorite = false,
    this.timesLogged = 0,
    this.lastUsedAt = 0,
  });

  final int? id;
  final String name;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber; // grams
  final double sugar; // grams
  final double sodium; // milligrams
  final bool isFavorite;
  final int timesLogged;
  final int lastUsedAt;

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'kcal': kcal,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'fiber': fiber,
      'sugar': sugar,
      'sodium': sodium,
      'is_favorite': isFavorite ? 1 : 0,
      'times_logged': timesLogged,
      'last_used_at': lastUsedAt,
    };
  }

  static FoodItem fromMap(Map<String, Object?> map) {
    return FoodItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      kcal: (map['kcal'] as num?)?.toDouble() ?? 0,
      protein: (map['protein'] as num?)?.toDouble() ?? 0,
      carbs: (map['carbs'] as num?)?.toDouble() ?? 0,
      fat: (map['fat'] as num?)?.toDouble() ?? 0,
      fiber: (map['fiber'] as num?)?.toDouble() ?? 0,
      sugar: (map['sugar'] as num?)?.toDouble() ?? 0,
      sodium: (map['sodium'] as num?)?.toDouble() ?? 0,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      timesLogged: map['times_logged'] as int? ?? 0,
      lastUsedAt: map['last_used_at'] as int? ?? 0,
    );
  }
}

/// A habit. Derived kinds are auto-checked from entries; [HabitKind.manual]
/// is toggled by hand.
class Habit {
  const Habit({
    this.id,
    required this.name,
    required this.kind,
    this.enabled = true,
    required this.createdAt,
  });

  final int? id;
  final String name;
  final HabitKind kind;
  final bool enabled;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'kind': kind.name,
      'enabled': enabled ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  static Habit fromMap(Map<String, Object?> map) {
    return Habit(
      id: map['id'] as int?,
      name: map['name'] as String,
      kind: HabitKind.values.byName(map['kind'] as String),
      enabled: (map['enabled'] as int? ?? 1) == 1,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}

/// A per-day done/not-done state for a habit (manual or derived override).
class HabitLog {
  const HabitLog({
    this.id,
    required this.habitId,
    required this.date,
    required this.done,
  });

  final int? id;
  final int habitId;
  final String date;
  final bool done;

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'habit_id': habitId,
      'date': date,
      'done': done ? 1 : 0,
    };
  }

  static HabitLog fromMap(Map<String, Object?> map) {
    return HabitLog(
      id: map['id'] as int?,
      habitId: map['habit_id'] as int,
      date: map['date'] as String,
      done: (map['done'] as int? ?? 0) == 1,
    );
  }
}
