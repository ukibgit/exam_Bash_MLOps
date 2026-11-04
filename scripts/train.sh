# -----------------------------------------------------------------------------
# This script train.sh runs the Python program src/train.py.
# This program trains a prediction model and saves the final model
# in the model/ directory. The script also logs all execution details
# in the file logs/train.logs.
# -----------------------------------------------------------------------------

#!/usr/bin/env bash

set -euo pipefail

# Project root directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# Python training script
PYTHON_SCRIPT="$PROJECT_DIR/src/train.py"

# Log directory and file
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/train.logs"

# Create log directory
mkdir -p "$LOG_DIR" "$PROJECT_DIR/model"

# Check Python script
if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    echo "ERROR: Training script not found: $PYTHON_SCRIPT" >&2
    exit 1
fi

# Start training and record output
echo "Starting GPU sales model training..."

if python3 "$PYTHON_SCRIPT" 2>&1 | tee -a "$LOG_FILE"; then
    echo "Training completed successfully."
else
    echo "ERROR: Model training failed. Check $LOG_FILE" >&2
    exit 1
fi
