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
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

RAW_DIR="$PROJECT_ROOT/data/raw"
RAW_CSV_FILE="$RAW_DIR/sales_data.csv"
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/collect.logs"

API_URL="http://0.0.0.0:5000/rtx3060"

mkdir -p "$RAW_DIR" "$LOG_DIR" "$LOG_DIR/test_logs" || {
    echo "ERROR: Cannot create required directories." >&2
    exit 1
}

log_message() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
        >> "$LOG_FILE"
}

# Preserve the existing template; never replace it.
if [[ ! -f "$RAW_CSV_FILE" ]]; then
    log_message "ERROR: Exam_Bash_MLOps CSV template not found: $RAW_CSV_FILE"
    exit 1
fi

EXPECTED_HEADER="timestamp,model,sales"
ACTUAL_HEADER="$(head -n 1 -- "$RAW_CSV_FILE")"

if [[ "$ACTUAL_HEADER" != "$EXPECTED_HEADER" ]]; then
    log_message "ERROR: Unexpected CSV template header: $ACTUAL_HEADER"
    exit 1
fi

RUN_TIMESTAMP="$(date '+%Y%m%d_%H%M')"
RAW_FILE="$RAW_DIR/sales_${RUN_TIMESTAMP}.csv"

# Never overwrite data from an earlier run.
if [[ -e "$RAW_FILE" ]]; then
    log_message "ERROR: Raw output already exists: $RAW_FILE"
    exit 1
fi

response_file="$(mktemp)"
trap 'rm -f -- "$response_file"' EXIT

log_message "INFO: Requesting sales data from API."

if ! curl -fsS --max-time 30 "$API_URL" -o "$response_file"; then
    log_message "ERROR: API request failed."
    exit 1
fi

if ! jq -e 'type == "array"' "$response_file" >/dev/null; then
    log_message "ERROR: API response is not a JSON array."
    exit 1
fi

# Create the output exclusively from the existing template.
# noclobber prevents replacing a file created by another process.
if ! (set -o noclobber; cat -- "$RAW_CSV_FILE" > "$RAW_FILE"); then
    log_message "ERROR: Cannot create raw output: $RAW_FILE"
    exit 1
fi

RETRIEVED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

if ! jq -r --arg retrieved_at "$RETRIEVED_AT" '
    .[]
    | select((.model // "") | type == "string")
    | select((.model | test("^(rtx|rx)"; "i")))
    | select(has("sales") and (.sales != null))
    | [
        (.timestamp // $retrieved_at),
        .model,
        .sales
      ]
    | @csv
' "$response_file" >> "$RAW_FILE"; then
    log_message "ERROR: Failed to convert API response to CSV."
    rm -f -- "$RAW_FILE"
    exit 1
fi

log_message "INFO: Raw data saved to $RAW_FILE"

# Pass the same run timestamp through to preprocessing.
if "$SCRIPT_DIR/preprocessed.sh" "$RAW_FILE" "$RUN_TIMESTAMP"; then
    log_message "INFO: Collection and preprocessing completed."
else
    status=$?
    log_message "ERROR: Preprocessing failed with exit code $status."
    exit "$status"
fi
