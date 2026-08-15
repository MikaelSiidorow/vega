import PowerSync

nonisolated enum WgerPowerSyncTable {
    static let userProfile = "core_userprofile"
    static let language = "core_language"
    static let repetitionUnit = "core_repetitionunit"
    static let weightUnit = "core_weightunit"

    static let ingredient = "nutrition_ingredient"
    static let ingredientImage = "nutrition_image"
    static let ingredientWeightUnit = "nutrition_ingredientweightunit"
    static let nutritionPlan = "nutrition_nutritionplan"
    static let meal = "nutrition_meal"
    static let mealItem = "nutrition_mealitem"
    static let logItem = "nutrition_logitem"

    static let weightEntry = "weight_weightentry"

    static let exercise = "exercises_exercise"
    static let exerciseTranslation = "exercises_translation"

    static let routine = "manager_routine"
    static let workoutLog = "manager_workoutlog"
    static let workoutSession = "manager_workoutsession"

    static let workoutDayCache = "vega_workout_day_cache"
    static let workoutSetPlanCache = "vega_workout_set_plan_cache"
    static let localCacheMetadata = "vega_local_cache_metadata"
}

/// The subset of Wger's official PowerSync schema consumed by Vega.
///
/// Column names and SQLite affinities intentionally match the Wger Flutter
/// client and server sync rules. PowerSync owns the text `id` column for every
/// table; server integer identifiers therefore remain text locally and are
/// decoded by Vega's typed repositories.
nonisolated let wgerPowerSyncSchema = Schema(
    Table(
        name: WgerPowerSyncTable.userProfile,
        columns: [.text("weight_unit")]
    ),
    Table(
        name: WgerPowerSyncTable.language,
        columns: [.text("short_name"), .text("full_name")]
    ),
    Table(
        name: WgerPowerSyncTable.repetitionUnit,
        columns: [.text("name")]
    ),
    Table(
        name: WgerPowerSyncTable.weightUnit,
        columns: [.text("name")]
    ),
    Table(
        name: WgerPowerSyncTable.ingredient,
        columns: [
            .text("uuid"),
            .integer("language_id"),
            .text("remote_id"),
            .text("source_name"),
            .text("source_url"),
            .text("license_object_url"),
            .text("code"),
            .text("name"),
            .text("brand"),
            .text("created"),
            .integer("energy"),
            .real("carbohydrates"),
            .real("carbohydrates_sugar"),
            .real("protein"),
            .real("fat"),
            .real("fat_saturated"),
            .real("fiber"),
            .real("sodium"),
            .integer("is_vegan"),
            .integer("is_vegetarian"),
            .text("nutriscore"),
        ],
        indexes: [Index(name: "language_idx", columns: [IndexedColumn.ascending("language_id")])]
    ),
    Table(
        name: WgerPowerSyncTable.ingredientImage,
        columns: [
            .text("uuid"),
            .integer("ingredient_id"),
            .text("image"),
            .integer("size"),
            .integer("width"),
            .integer("height"),
            .text("created"),
            .text("last_update"),
            .integer("license_id"),
            .text("license_author"),
            .text("license_author_url"),
            .text("license_title"),
            .text("license_object_url"),
            .text("license_derivative_source_url"),
        ],
        indexes: [
            Index(name: "ingredient_idx", columns: [IndexedColumn.ascending("ingredient_id")])
        ]
    ),
    Table(
        name: WgerPowerSyncTable.ingredientWeightUnit,
        columns: [
            .text("uuid"),
            .integer("ingredient_id"),
            .text("name"),
            .integer("gram"),
        ],
        indexes: [
            Index(name: "ingredient_idx", columns: [IndexedColumn.ascending("ingredient_id")])
        ]
    ),
    Table(
        name: WgerPowerSyncTable.nutritionPlan,
        columns: [
            .text("description"),
            .text("creation_date"),
            .text("start"),
            .text("end"),
            .integer("only_logging"),
            .integer("goal_energy"),
            .integer("goal_protein"),
            .integer("goal_carbohydrates"),
            .integer("goal_fiber"),
            .integer("goal_fat"),
            .integer("has_goal_calories"),
        ]
    ),
    Table(
        name: WgerPowerSyncTable.meal,
        columns: [
            .text("plan_id"),
            .integer("order"),
            .text("time"),
            .text("name"),
        ],
        indexes: [Index(name: "plan_idx", columns: [IndexedColumn.ascending("plan_id")])]
    ),
    Table(
        name: WgerPowerSyncTable.mealItem,
        columns: [
            .text("meal_id"),
            .integer("ingredient_id"),
            .integer("weight_unit_id"),
            .integer("order"),
            .real("amount"),
        ],
        indexes: [
            Index(name: "meal_idx", columns: [IndexedColumn.ascending("meal_id")]),
            Index(name: "ingredient_idx", columns: [IndexedColumn.ascending("ingredient_id")]),
        ]
    ),
    Table(
        name: WgerPowerSyncTable.logItem,
        columns: [
            .text("plan_id"),
            .text("meal_id"),
            .integer("ingredient_id"),
            .integer("weight_unit_id"),
            .text("datetime"),
            .real("amount"),
            .text("comment"),
        ],
        indexes: [
            Index(name: "plan_idx", columns: [IndexedColumn.ascending("plan_id")]),
            Index(name: "ingredient_idx", columns: [IndexedColumn.ascending("ingredient_id")]),
        ]
    ),
    Table(
        name: WgerPowerSyncTable.weightEntry,
        columns: [.real("weight"), .text("date")]
    ),
    Table(
        name: WgerPowerSyncTable.exercise,
        columns: [
            .text("uuid"),
            .text("variation_group"),
            .integer("category_id"),
            .text("created"),
            .text("last_update"),
        ]
    ),
    Table(
        name: WgerPowerSyncTable.exerciseTranslation,
        columns: [
            .text("uuid"),
            .integer("exercise_id"),
            .integer("language_id"),
            .text("name"),
            .text("description"),
            .text("created"),
            .text("last_update"),
        ],
        indexes: [
            Index(name: "exercise_idx", columns: [IndexedColumn.ascending("exercise_id")]),
            Index(name: "language_idx", columns: [IndexedColumn.ascending("language_id")]),
        ]
    ),
    Table(
        name: WgerPowerSyncTable.routine,
        columns: [
            .text("name"),
            .text("description"),
            .text("created"),
            .text("start"),
            .text("end"),
            .integer("is_template"),
            .integer("is_public"),
            .integer("fit_in_week"),
        ]
    ),
    Table(
        name: WgerPowerSyncTable.workoutLog,
        columns: [
            .integer("exercise_id"),
            .integer("routine_id"),
            .text("session_id"),
            .integer("iteration"),
            .integer("slot_entry_id"),
            .real("rir"),
            .real("rir_target"),
            .real("repetitions"),
            .real("repetitions_target"),
            .integer("repetitions_unit_id"),
            .real("weight"),
            .real("weight_target"),
            .integer("weight_unit_id"),
            .text("date"),
        ],
        indexes: [
            Index(name: "exercise_idx", columns: [IndexedColumn.ascending("exercise_id")]),
            Index(name: "slot_entry_idx", columns: [IndexedColumn.ascending("slot_entry_id")]),
            Index(name: "routine_idx", columns: [IndexedColumn.ascending("routine_id")]),
            Index(name: "session_idx", columns: [IndexedColumn.ascending("session_id")]),
        ]
    ),
    Table(
        name: WgerPowerSyncTable.workoutSession,
        columns: [
            .integer("routine_id"),
            .integer("day_id"),
            .text("date"),
            .text("notes"),
            .text("impression"),
            .text("time_start"),
            .text("time_end"),
        ],
        indexes: [
            Index(name: "routine_idx", columns: [IndexedColumn.ascending("routine_id")]),
            Index(name: "day_idx", columns: [IndexedColumn.ascending("day_id")]),
        ]
    ),
    Table(
        name: WgerPowerSyncTable.workoutDayCache,
        columns: [
            .integer("routine_id"),
            .integer("day_id"),
            .text("name"),
            .text("date"),
            .integer("iteration"),
            .integer("is_rest"),
        ],
        indexes: [
            Index(name: "routine_idx", columns: [IndexedColumn.ascending("routine_id")]),
            Index(name: "date_idx", columns: [IndexedColumn.ascending("date")]),
        ],
        localOnly: true
    ),
    Table(
        name: WgerPowerSyncTable.workoutSetPlanCache,
        columns: [
            .text("day_cache_id"),
            .integer("slot_entry_id"),
            .integer("exercise_id"),
            .integer("set_count"),
            .text("target_repetitions"),
            .text("target_weight"),
            .integer("repetitions_unit_id"),
            .integer("weight_unit_id"),
            .text("repetitions_increment"),
            .text("weight_increment"),
            .text("rest"),
            .text("prescription"),
            .text("comment"),
        ],
        indexes: [
            Index(name: "day_cache_idx", columns: [IndexedColumn.ascending("day_cache_id")])
        ],
        localOnly: true
    ),
    Table(
        name: WgerPowerSyncTable.localCacheMetadata,
        columns: [.text("updated_at")],
        localOnly: true
    )
)
