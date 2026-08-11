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
