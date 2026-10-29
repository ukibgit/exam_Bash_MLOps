# ==============================================================================
# Script: collect.sh
# Description:
#   This script queries an API to retrieve sales data for the following graphics card models:
#     - rtx3060
#     - rtx3070
#     - rtx3080
#     - rtx3090
#     - rx6700
#
#   The collected data is appended to a copy of the file:
#     data/raw/sales_data.csv
#
#   The output file is saved in the format:
#     data/raw/sales_YYYYMMDD_HHMM.csv
#   with the following columns:
#     timestamp, model, sales
#
#   Collection activity (requests, queried models, results, errors)
#   is recorded in a log file:
#     logs/collect.logs
#
#   The log should be human-readable and must include:
#     - The date and time of each request
#     - The queried models
#     - The retrieved sales data
#     - Any possible errors
# ==============================================================================

#!/usr/bin/env bash

set -u
set -o pipefail

# --------------------------------------------------
# Configuration
# --------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CSV_FILE="$SCRIPT_DIR/sales.csv"
LOG_DIR="$SCRIPT_DIR/log"
LOG_FILE="$LOG_DIR/check.log"

# Replace this URL with your actual API endpoint.
API_URL="https://api.example.com/sales"

# --------------------------------------------------
# Initialisation
# --------------------------------------------------

mkdir -p "$LOG_DIR" || {
    echo "ERROR: Cannot create log directory: $LOG_DIR" >&2
    exit 1
}

# Check required commands
for command in curl jq; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "ERROR: Required command '$command' is not installed." >&2
        printf '%s ERROR: Required command %s is not installed.\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$command" >> "$LOG_FILE"
        exit 1
    fi
done

# Create CSV with a header if it does not exist or is empty.
if [[ ! -s "$CSV_FILE" ]]; then
    printf '"timestamp","model","sales"\n' > "$CSV_FILE" || {
        echo "ERROR: Cannot write to $CSV_FILE" >&2
        exit 1
    }
fi

# Temporary file for the API response
response_file="$(mktemp)" || {
    echo "ERROR: Cannot create temporary file." >&2
    exit 1
}

trap 'rm -f "$response_file"' EXIT

# --------------------------------------------------
# Request data from API
# --------------------------------------------------

timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

printf '%s INFO: Starting sales API request.\n' \
    "$timestamp" >> "$LOG_FILE"

printf '%s INFO: API endpoint: %s\n' \
    "$timestamp" "$API_URL" >> "$LOG_FILE"

if ! curl -fsS --max-time 30 \
    "$API_URL" \
    -o "$response_file" \
    2>> "$LOG_FILE"; then

    printf '%s ERROR: API request failed.\n' \
        "$timestamp" >> "$LOG_FILE"

    exit 1
fi

printf '%s INFO: API response received.\n' \
    "$timestamp" >> "$LOG_FILE"

# --------------------------------------------------
# Validate JSON response
# --------------------------------------------------

if ! jq -e 'type == "array"' "$response_file" >/dev/null 2>&1; then
    printf '%s ERROR: API response is not a valid JSON array.\n' \
        "$timestamp" >> "$LOG_FILE"

    exit 1
fi

# --------------------------------------------------
# Filter models beginning with atv or av
# --------------------------------------------------

filtered="$(jq -c '
    [
        .[] |
        select(
            (.model | type == "string") and
            (.model | test("^(atv|av)"; "i")) and
            has("sales")
        )
    ]
' "$response_file")" || {
    printf '%s ERROR: Failed to filter API response.\n' \
        "$timestamp" >> "$LOG_FILE"
    exit 1
}

# --------------------------------------------------
# Log matching models and their sales
# --------------------------------------------------

matching_count="$(jq 'length' <<< "$filtered")" || {
    printf '%s ERROR: Failed to count matching records.\n' \
        "$timestamp" >> "$LOG_FILE"
    exit 1
}

printf '%s INFO: Matching records found: %s\n' \
    "$timestamp" "$matching_count" >> "$LOG_FILE"

if [[ "$matching_count" -eq 0 ]]; then
    printf '%s INFO: No matching atv or av models found.\n' \
        "$timestamp" >> "$LOG_FILE"
else
    jq -r --arg timestamp "$timestamp" '
        .[] |
        if (.model | test("^atv"; "i")) then
            "\($timestamp) INFO: category=national, model=\(.model), sales=\(.sales)"
        else
            "\($timestamp) INFO: category=international, model=\(.model), sales=\(.sales)"
        end
    ' <<< "$filtered" >> "$LOG_FILE" || {
        printf '%s ERROR: Failed to write model details to log.\n' \
            "$timestamp" >> "$LOG_FILE"
        exit 1
    }

    # --------------------------------------------------
    # Append matching records to CSV
    # --------------------------------------------------

    if ! jq -r --arg timestamp "$timestamp" '
        .[] |
        [$timestamp, .model, (.sales | tostring)] |
        @csv
    ' <<< "$filtered" >> "$CSV_FILE"; then

        printf '%s ERROR: Failed to write records to CSV.\n' \
            "$timestamp" >> "$LOG_FILE"

        exit 1
    fi

    printf '%s INFO: %s records appended to %s\n' \
        "$timestamp" "$matching_count" "$CSV_FILE" >> "$LOG_FILE"
fi

printf '%s INFO: Request completed successfully.\n' \
    "$timestamp" >> "$LOG_FILE"

exit 0
