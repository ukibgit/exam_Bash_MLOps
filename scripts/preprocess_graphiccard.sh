# =============================================================================
# This script preprocessed.sh runs the program src/preprocessed.py
# and logs the execution details in the log file
# logs/preprocessed.logs.
# =============================================================================

#!/usr/bin/env bash

set -u
set -o pipefail

# --------------------------------------------------
# Configuration
# --------------------------------------------------

# Resolve project_root from this script's location.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Raw input and processed output
RAW_DIR="$PROJECT_ROOT/data/raw"
INPUT_FILE="$RAW_DIR/sales_data.csv"

PROCESSED_DIR="$PROJECT_ROOT/data/processed"
OUTPUT_FILE="$PROCESSED_DIR/sales_data.csv"

# Preprocessing logs
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/preprocessed.logs"

# Python preprocessing implementation
SRC_DIR="$PROJECT_ROOT/src"
PYTHON_SCRIPT="$SRC_DIR/preprocessed.py"

# --------------------------------------------------
# Logging
# --------------------------------------------------

mkdir -p "$PROCESSED_DIR" "$LOG_DIR" || {
    echo "ERROR: Cannot create preprocessing directories." >&2
    exit 1
}

log_message() {
    printf '%s %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

log_message "INFO: Preprocessing started."

# --------------------------------------------------
# Precondition checks
# --------------------------------------------------

if [[ ! -f "$INPUT_FILE" ]]; then
    log_message "ERROR: Input CSV not found: $INPUT_FILE"
    echo "ERROR: Input CSV not found: $INPUT_FILE" >&2
    exit 1
fi

if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    log_message "ERROR: Python script not found: $PYTHON_SCRIPT"
    echo "ERROR: Python script not found: $PYTHON_SCRIPT" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    log_message "ERROR: Python 3 is unavailable."
    echo "ERROR: Python 3 is required." >&2
    exit 1
fi

# --------------------------------------------------
# Execute Python preprocessing
# --------------------------------------------------

if python3 "$PYTHON_SCRIPT" \
    --input "$INPUT_FILE" \
    --output "$OUTPUT_FILE" \
    >> "$LOG_FILE" 2>&1; then

    log_message "INFO: Preprocessing completed successfully."
else
    status=$?
    log_message "ERROR: Python preprocessing failed with exit code $status."
    exit "$status"
fi

exit 0
