# =============================================================================
# This script preprocessed.sh runs the program src/preprocessed.py
# and logs the execution details in the log file
# logs/preprocessed.logs.
# =============================================================================

#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

PROCESSED_DIR="$PROJECT_ROOT/data/processed"

LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/preprocessed.logs"

SRC_DIR="$PROJECT_ROOT/src"

PYTHON_SCRIPT="$SRC_DIR/preprocessed.py"

mkdir -p "$PROCESSED_DIR" "$LOG_DIR" || {
    echo "ERROR: Cannot create preprocessing directories." >&2
    exit 1
}

log_message() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
        >> "$LOG_FILE"
}

if [[ $# -ne 2 ]]; then
    log_message "ERROR: Usage: preprocessed.sh RAW_FILE YYYYMMDD_HHMM"
    exit 2
fi

INPUT_FILE="$1"
RUN_TIMESTAMP="$2"
OUTPUT_FILE="$PROCESSED_DIR/sales_processed_${RUN_TIMESTAMP}.csv"

if [[ ! -f "$INPUT_FILE" ]]; then
    log_message "ERROR: Input file not found: $INPUT_FILE"
    exit 1
fi

if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    log_message "ERROR: Python script not found: $PYTHON_SCRIPT"
    exit 1
fi

if [[ ! "$RUN_TIMESTAMP" =~ ^[0-9]{8}_[0-9]{4}$ ]]; then
    log_message "ERROR: Invalid run timestamp: $RUN_TIMESTAMP"
    exit 1
fi

if [[ -e "$OUTPUT_FILE" ]]; then
    log_message "ERROR: Processed output already exists: $OUTPUT_FILE"
    exit 1
fi

log_message "INFO: Processing $INPUT_FILE"

if python3 "$PYTHON_SCRIPT" \
    --input "$INPUT_FILE" \
    --output "$OUTPUT_FILE" \
    >> "$LOG_FILE" 2>&1; then
    log_message "INFO: Processed data saved to $OUTPUT_FILE"
else
    status=$?
    log_message "ERROR: Python preprocessing failed with exit code $status"
    exit "$status"
fi
