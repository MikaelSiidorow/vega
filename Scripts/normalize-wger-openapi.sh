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
    # The PowerSync delete endpoint consumes the same record envelope as its
    # put and patch siblings, but wger 2.7 omits that request body from OpenAPI.
    .paths["/api/v2/upload-powersync-data"].delete.requestBody =
        .paths["/api/v2/upload-powersync-data"].put.requestBody
    |
    # The gym response can contain null for unset targets and rounding values,
    # while the 2.7 schema marks those required fields as non-null strings.
    .components.schemas.SetConfigData.properties |= with_entries(
        .key as $key
        | if ([
            "max_sets", "weight", "max_weight", "weight_unit", "weight_rounding",
            "repetitions", "max_repetitions", "repetitions_unit",
            "repetitions_rounding", "rir", "max_rir", "rpe", "rest", "max_rest"
        ] | index($key)) != null
        then .value.nullable = true
        else .
        end
    )
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

# These response contracts were incorrect in wger 2.6. Keep the refresh strict
# so an older or regressed server schema cannot silently replace the snapshot.
if ! jq -e '
    .paths["/api/v2/upload-powersync-data"].delete.requestBody
        .content["application/json"].schema."$ref"
        == "#/components/schemas/PowersyncUploadRequest"
' "$output_schema" >/dev/null; then
    echo "PowerSync delete request normalization failed" >&2
    exit 1
fi

if ! jq -e '
    .components.schemas.IngredientInfo.properties.image.nullable == true
    and .components.schemas.IngredientInfo.properties.thumbnails.nullable == true
    and .components.schemas.IngredientInfo.properties.thumbnails.allOf[0]."$ref"
        == "#/components/schemas/Thumbnails"
' "$output_schema" >/dev/null; then
    echo "Ingredient image contract validation failed" >&2
    exit 1
fi

if ! jq -e '
    (.paths["/api/v2/routine/{id}/date-sequence-gym/"]
        .get.responses["200"].content["application/json"].schema.type == "array")
    and (.paths["/api/v2/routine/{id}/date-sequence-gym/"]
        .get.responses["200"].content["application/json"].schema.items."$ref"
        == "#/components/schemas/WorkoutDayDataGymMode")
    and ([
        .components.schemas.SetConfigData.properties[
            "max_sets", "weight", "max_weight", "weight_unit", "weight_rounding",
            "repetitions", "max_repetitions", "repetitions_unit",
            "repetitions_rounding", "rir", "max_rir", "rpe", "rest", "max_rest"
        ].nullable
    ] | all)
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
