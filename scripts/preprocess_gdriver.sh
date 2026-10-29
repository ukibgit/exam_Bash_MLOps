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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

INPUT_FILE="$SCRIPT_DIR/sales.csv"
OUTPUT_FILE="$SCRIPT_DIR/processed_sales.csv"
LOG_FILE="$SCRIPT_DIR/log/preprocess.log"

# --------------------------------------------------
# Initial checks
# --------------------------------------------------

mkdir -p "$SCRIPT_DIR/log" || {
    echo "ERROR: Cannot create log directory." >&2
    exit 1
}

log_message() {
    printf '%s %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$1" \
        >> "$LOG_FILE"
}

log_message "INFO: Data preprocessing started."

# Check that the input file exists.
if [[ ! -f "$INPUT_FILE" ]]; then
    log_message "ERROR: Input CSV file not found."
    echo "ERROR: Input CSV file not found: $INPUT_FILE" >&2
    exit 1
fi

# Check required Python interpreter.
if ! command -v python3 >/dev/null 2>&1; then
    log_message "ERROR: Python 3 is not installed or not in PATH."
    echo "ERROR: Python 3 is required." >&2
    exit 1
fi

# --------------------------------------------------
# Data preprocessing
# --------------------------------------------------

if python3 - "$INPUT_FILE" "$OUTPUT_FILE" <<'PY'
import csv
import re
import sys
from collections import defaultdict
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path

input_file = Path(sys.argv[1])
output_file = Path(sys.argv[2])

required_columns = {"timestamp", "model", "sales"}
aggregated = defaultdict(lambda: Decimal("0"))
record_counts = defaultdict(int)

total_rows = 0
invalid_rows = 0
filtered_rows = 0
valid_rows = 0


def parse_timestamp(value):
    """Convert a supported timestamp to a date."""
    value = value.strip()

    if not value:
        raise ValueError("Missing timestamp")

    # Support ISO timestamps ending in Z.
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"

    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as exc:
        raise ValueError("Invalid timestamp") from exc

    return parsed.date().isoformat()


def parse_sales(value):
    """Convert sales to a finite decimal number."""
    value = value.strip()

    if not value:
        raise ValueError("Missing sales value")

    try:
        number = Decimal(value)
    except InvalidOperation as exc:
        raise ValueError("Sales is not numeric") from exc

    if not number.is_finite():
        raise ValueError("Sales is not finite")

    return number


try:
    with input_file.open(
        "r", encoding="utf-8-sig", newline=""
    ) as source:
        reader = csv.DictReader(source)

        if reader.fieldnames is None:
            raise ValueError("CSV file has no header")

        reader.fieldnames = [
            name.strip() for name in reader.fieldnames
        ]

        if not required_columns.issubset(reader.fieldnames):
            raise ValueError(
                "CSV header must contain timestamp, model, sales"
            )

        for row in reader:
            total_rows += 1

            try:
                # 1. Validate and normalize fields.
                timestamp = parse_timestamp(
                    row.get("timestamp") or ""
                )

                model = (row.get("model") or "").strip()

                if not model:
                    raise ValueError("Missing model")

                sales = parse_sales(row.get("sales") or "")

            except ValueError:
                invalid_rows += 1
                continue

            # 2. Filter for the required model prefixes.
            if not re.match(r"^(atv|av)", model, re.IGNORECASE):
                filtered_rows += 1
                continue

            # 3. Aggregate sales by date and model.
            key = (timestamp, model)
            aggregated[key] += sales
            record_counts[key] += 1
            valid_rows += 1

    # Write a separate output file; preserve the source CSV.
    with output_file.open(
        "w", encoding="utf-8", newline=""
    ) as destination:
        writer = csv.writer(destination)
        writer.writerow(
            ["date", "model", "total_sales", "record_count"]
        )

        for (date, model), total in sorted(aggregated.items()):
            writer.writerow([
                date,
                model,
                format(total, "f"),
                record_counts[(date, model)],
            ])

except (OSError, ValueError, csv.Error) as exc:
    print(f"ERROR: Preprocessing failed: {exc}", file=sys.stderr)
    sys.exit(1)

print(f"Rows read: {total_rows}")
print(f"Valid records retained: {valid_rows}")
print(f"Invalid records removed: {invalid_rows}")
print(f"Other models filtered out: {filtered_rows}")
print(f"Aggregated groups: {len(aggregated)}")
print(f"Output: {output_file}")

PY
then
    log_message "INFO: Data preprocessing completed successfully."
else
    log_message "ERROR: Data preprocessing failed."
    exit 1
fi

exit 0
