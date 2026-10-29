
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

RAW_DIR="$PROJECT_ROOT/data/raw"
TEMPLATE_FILE="$RAW_DIR/sales_data.csv"

LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/collect.logs"

# Use the local client address, not the server binding address.
API_BASE="http://127.0.0.1:5000"

MODELS=(rtx3060 rtx3070 rtx3080 rtx3090 rx6700)
PREPROCESS_SCRIPT="$SCRIPT_DIR/preprocessed.sh"

mkdir -p "$RAW_DIR" "$LOG_DIR" "$LOG_DIR/test_logs" || {
    echo "ERROR: Cannot create required directories." >&2
    exit 1
}

log_message() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
        >> "$LOG_FILE"
}

# Validate the existing template without modifying it.
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_message "ERROR: CSV template not found: $TEMPLATE_FILE"
    exit 1
fi

EXPECTED_HEADER="timestamp,model,sales"
ACTUAL_HEADER="$(head -n 1 -- "$TEMPLATE_FILE")"

if [[ "$ACTUAL_HEADER" != "$EXPECTED_HEADER" ]]; then
    log_message "ERROR: Unexpected CSV template header: $ACTUAL_HEADER"
    exit 1
fi

if [[ ! -x "$PREPROCESS_SCRIPT" ]]; then
    log_message "ERROR: Preprocessing script missing or not executable: $PREPROCESS_SCRIPT"
    exit 1
fi

RUN_TIMESTAMP="$(date '+%Y%m%d_%H%M')"
RAW_FILE="$RAW_DIR/sales_data_${RUN_TIMESTAMP}.csv"
RETRIEVED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Do not overwrite an existing snapshot.
if [[ -e "$RAW_FILE" ]]; then
    log_message "ERROR: Raw output already exists: $RAW_FILE"
    exit 1
fi

# Collect and validate all readings before creating the output file.
# This prevents a failed endpoint from producing an incomplete snapshot.
ROWS=""

for model in "${MODELS[@]}"; do
    API_URL="$API_BASE/$model"
    log_message "INFO: Requesting GPU model $model from $API_URL"

    if ! response="$(curl -fsS --max-time 30 "$API_URL")"; then
        log_message "ERROR: API request failed for $model"
        exit 1
    fi

    if ! sales="$(jq -er '
        if type == "number" and . >= 0
        then tostring
        else error("Expected a non-negative numeric sales value")
        end
    ' <<< "$response" 2>/dev/null)"; then
        log_message "ERROR: Invalid sales response for $model: $response"
        exit 1
    fi

    row="$(jq -nr \
        --arg timestamp "$RETRIEVED_AT" \
        --arg model "$model" \
        --argjson sales "$sales" \
        '[$timestamp, $model, $sales] | @csv')"

    ROWS+="$row"$'\n'
    log_message "INFO: Retrieved model=$model sales=$sales"
done

# Create the snapshot exclusively, preserving the template's contents.
if ! (set -o noclobber; cat -- "$TEMPLATE_FILE" > "$RAW_FILE"); then
    log_message "ERROR: Cannot create raw output: $RAW_FILE"
    exit 1
fi

# Ensure the template ends with a newline before appending new records.
LAST_BYTE="$(tail -c 1 "$RAW_FILE" | od -An -t x1 | tr -d '[:space:]')"

if [[ -n "$LAST_BYTE" && "$LAST_BYTE" != "0a" ]]; then
    if ! printf '\n' >> "$RAW_FILE"; then
        log_message "ERROR: Failed to add newline to $RAW_FILE"
        exit 1
    fi
fi

# Append only after all five endpoint responses have passed validation.
if ! printf '%s' "$ROWS" >> "$RAW_FILE"; then
    log_message "ERROR: Failed to append GPU readings to $RAW_FILE"
    exit 1
fi

log_message "INFO: Raw data saved to $RAW_FILE"

# Reuse the same timestamp for the processed output.
if "$PREPROCESS_SCRIPT" "$RAW_FILE" "$RUN_TIMESTAMP"; then
    log_message "INFO: Collection and preprocessing completed successfully."
else
    status=$?
    log_message "ERROR: Preprocessing failed with exit code $status"
    exit "$status"
fi
