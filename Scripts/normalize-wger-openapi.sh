#!/bin/sh

set -eu

source_schema="$1"
output_schema="$2"

# Django REST Framework advertises the same request model for JSON, form, and
# multipart bodies. Swift OpenAPI Generator turns multipart models into stream
# enums, which makes the same model unusable as JSON. Vega uses JSON for REST
# mutations, so retain that representation wherever the server provides it.
#
# File uploads need multipart request schemas, but wger reuses those schemas for
# JSON, form, and multipart bodies. Until uploads are implemented deliberately,
# omit only the affected write operations and their request-only schemas. Read
# and delete operations remain generated.
jq '
    .components.schemas.IngredientThumbnails = {
        "type": "object",
        "description": "Thumbnail URLs generated for an ingredient image.",
        "properties": {
            "small": {"type": "string", "format": "uri"},
            "medium": {"type": "string", "format": "uri"}
        },
        "required": ["small", "medium"]
    }
    | .components.schemas.IngredientInfo.properties.image.nullable = true
    | .components.schemas.IngredientInfo.properties.thumbnails = {
        "allOf": [{"$ref": "#/components/schemas/IngredientThumbnails"}],
        "nullable": true,
        "readOnly": true
    }
    # The custom action uses NutritionalValuesSerializer, but schema generation
    # infers the viewset default NutritionPlan serializer.
    | .paths["/api/v2/nutritionplan/{id}/nutritional_values/"]
        .get.responses["200"].content["application/json"].schema = {
            "$ref": "#/components/schemas/NutritionalValues"
        }
    # The custom gym action returns WorkoutDayDataGymModeSerializer(many=True),
    # but schema generation infers the viewset default Routine serializer.
    | .components.schemas.WorkoutSetPlan = {
        "type": "object",
        "description": "One resolved exercise prescription in a workout slot.",
        "properties": {
            "slot_entry_id": {"type": "integer"},
            "exercise": {"type": "integer"},
            "sets": {"type": "integer"},
            "max_sets": {"type": "integer", "nullable": true},
            "weight": {"type": "string", "format": "decimal", "nullable": true},
            "max_weight": {"type": "string", "format": "decimal", "nullable": true},
            "weight_unit": {"type": "integer", "nullable": true},
            "weight_rounding": {"type": "string", "format": "decimal", "nullable": true},
            "repetitions": {"type": "string", "format": "decimal", "nullable": true},
            "max_repetitions": {"type": "string", "format": "decimal", "nullable": true},
            "repetitions_unit": {"type": "integer", "nullable": true},
            "repetitions_rounding": {
                "type": "string", "format": "decimal", "nullable": true
            },
            "rir": {"type": "string", "format": "decimal", "nullable": true},
            "max_rir": {"type": "string", "format": "decimal", "nullable": true},
            "rpe": {"type": "string", "format": "decimal", "nullable": true},
            "rest": {"type": "string", "format": "decimal", "nullable": true},
            "max_rest": {"type": "string", "format": "decimal", "nullable": true},
            "type": {"type": "string"},
            "text_repr": {"type": "string"},
            "comment": {"type": "string"}
        },
        "required": [
            "slot_entry_id", "exercise", "sets", "max_sets", "weight", "max_weight",
            "weight_unit", "weight_rounding", "repetitions", "max_repetitions",
            "repetitions_unit", "repetitions_rounding", "rir", "max_rir", "rpe", "rest",
            "max_rest", "type", "text_repr", "comment"
        ]
    }
    | .components.schemas.WorkoutSlotPlan = {
        "type": "object",
        "properties": {
            "comment": {"type": "string"},
            "is_superset": {"type": "boolean"},
            "exercises": {"type": "array", "items": {"type": "integer"}},
            "sets": {
                "type": "array",
                "items": {"$ref": "#/components/schemas/WorkoutSetPlan"}
            }
        },
        "required": ["comment", "is_superset", "exercises", "sets"]
    }
    | .components.schemas.WorkoutDayPlan = {
        "type": "object",
        "properties": {
            "iteration": {"type": "integer"},
            "date": {"type": "string", "format": "date"},
            "label": {"type": "string"},
            "day": {"$ref": "#/components/schemas/Day"},
            "slots": {
                "type": "array",
                "items": {"$ref": "#/components/schemas/WorkoutSlotPlan"}
            }
        },
        "required": ["iteration", "date", "label", "day", "slots"]
    }
    | .paths["/api/v2/routine/{id}/date-sequence-gym/"]
        .get.responses["200"].content["application/json"].schema = {
            "type": "array",
            "items": {"$ref": "#/components/schemas/WorkoutDayPlan"}
        }
    |
    del(
        .paths["/api/v2/exerciseimage/"].post,
        .paths["/api/v2/exerciseimage/{id}/"].put,
        .paths["/api/v2/exerciseimage/{id}/"].patch,
        .paths["/api/v2/gallery/"].post,
        .paths["/api/v2/gallery/{id}/"].put,
        .paths["/api/v2/gallery/{id}/"].patch,
        .paths["/api/v2/video/"].post,
        .paths["/api/v2/video/{id}/"].put,
        .paths["/api/v2/video/{id}/"].patch,
        .components.schemas.ExerciseImageRequest,
        .components.schemas.ExerciseVideoRequest,
        .components.schemas.ImageRequest,
        .components.schemas.IngredientImageRequest,
        .components.schemas.PatchedExerciseImageRequest,
        .components.schemas.PatchedExerciseVideoRequest,
        .components.schemas.PatchedImageRequest
    )
    | walk(
        if type == "object"
            and (.requestBody?.content?["application/json"] != null)
        then
            .requestBody.content |= with_entries(
                select(.key == "application/json")
            )
        else
            .
        end
    )
' "$source_schema" > "$output_schema"

# The serializer explicitly returns null when an ingredient has no usable
# image. Older wger schemas documented both values as non-null (and thumbnails
# as a string), so keep the generated contract aligned with the actual API.
if ! jq -e '
    .components.schemas.IngredientInfo.properties.image.nullable == true
    and .components.schemas.IngredientInfo.properties.thumbnails.nullable == true
    and .components.schemas.IngredientThumbnails.required == ["small", "medium"]
' "$output_schema" >/dev/null; then
    echo "Ingredient image nullability normalization failed" >&2
    exit 1
fi

if ! jq -e '
    (.paths["/api/v2/routine/{id}/date-sequence-gym/"]
        .get.responses["200"].content["application/json"].schema.type == "array")
    and (.components.schemas.WorkoutSetPlan.required | index("slot_entry_id") != null)
' "$output_schema" >/dev/null; then
    echo "Workout day response normalization failed" >&2
    exit 1
fi

if ! jq -e '
    .paths["/api/v2/nutritionplan/{id}/nutritional_values/"]
        .get.responses["200"].content["application/json"].schema."$ref"
        == "#/components/schemas/NutritionalValues"
' "$output_schema" >/dev/null; then
    echo "Nutrition plan values response normalization failed" >&2
    exit 1
fi

if ! jq -e '
    [
        .components.schemas[]
        | ..
        | objects
        | select(.type? == "string" and .format? == "binary")
    ]
    | length == 0
' "$output_schema" >/dev/null; then
    echo "Unsupported binary properties remain in the generated schema" >&2
    exit 1
fi
