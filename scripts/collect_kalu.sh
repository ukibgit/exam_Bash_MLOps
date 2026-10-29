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

# handle unidentified variable as an error
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
API_URL="https://api.example.com/sales"
CSV_FILE="$SCRIPT_DIR/sales.csv"
LOG_FILE="$SCRIPT_DIR/log/check.log"

mkdir -p "$SCRIPT_DIR/log"

if [[ ! -s "$CSV_FILE" ]]; then
    echo 'timestamp,model,sales' > "$CSV_FILE"
fi

timestamp=$(date '+%Y-%m-%d %H:%M:%S')
response_file=$(mktemp)

trap 'rm -f "$response_file"' EXIT

printf '[%s] REQUEST: GET sales API; model prefix=atv\n' \
    "$timestamp" >> "$LOG_FILE"

if curl -fsS --max-time 30 \
    -o "$response_file" "$API_URL" 2>> "$LOG_FILE"; then

    if jq -e 'type == "array"' "$response_file" >/dev/null 2>&1; then


        # Keep national (atv) and international (av) products
        filtered=$(jq -c '
            [
                .[] |
                select(
                    (.model | type == "string") and
                    (.model | test("^(atv|av)"; "i")) and
                    has("sales")
                )
            ]
        ' "$response_file")



        printf '[%s] FILTER: model prefix=atv\n' \
            "$timestamp" >> "$LOG_FILE"

        models=$(jq -r '[.[].model] | join(", ")' <<< "$filtered")
        printf '[%s] QUERIED/RETURNED MODELS: %s\n' \
            "$timestamp" "${models:-none}" >> "$LOG_FILE"

        if jq -r --arg ts "$timestamp" '
            .[] | [$ts, .model, .sales] | @csv
        ' <<< "$filtered" >> "$CSV_FILE"; then

            jq -r '.[] | "  model=\(.model), sales=\(.sales)"' \
                <<< "$filtered" >> "$LOG_FILE"

            count=$(jq 'length' <<< "$filtered")
            printf '[%s] RESULT: SUCCESS; records=%s\n' \
                "$timestamp" "$count" >> "$LOG_FILE"
        else
            printf '[%s] ERROR: Failed to write sales CSV\n' \
                "$timestamp" >> "$LOG_FILE"
        fi
    else
        printf '[%s] ERROR: API response is not a JSON array\n' \
            "$timestamp" >> "$LOG_FILE"
    fi
else
    printf '[%s] ERROR: API request failed\n' \
        "$timestamp" >> "$LOG_FILE"
fi
