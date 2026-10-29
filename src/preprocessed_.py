"""
-------------------------------------------------------------------------------
This script `preprocessed.py` retrieves data from the latest CSV file created 
in the 'data/raw/' directory.

1. It applies preprocessing to the data.
   
2. The results of the preprocessing are saved in a new CSV file 
   in the 'data/processed/' directory, with a name formatted as 
   'sales_processed_YYYYMMDD_HHMM.csv'.
   
3. All preprocessing steps are logged in the 
   'logs/preprocessed.logs' file to ensure detailed tracking of the process.

Any errors or anomalies are also logged to ensure traceability.
-------------------------------------------------------------------------------
"""

#!/usr/bin/env python3

import argparse
import csv
import re
import sys
from collections import defaultdict
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path


EXPECTED_HEADER = ["timestamp", "model", "sales"]
MODEL_PATTERN = re.compile(r"^(rtx|rx)", re.IGNORECASE)


def normalize_date(value: str) -> str:
    """Convert an ISO timestamp to YYYY-MM-DD."""
    value = value.strip()

    if value.endswith("Z"):
        value = value[:-1] + "+00:00"

    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as exc:
        raise ValueError(f"Invalid timestamp: {value!r}") from exc

    return parsed.date().isoformat()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate, filter, and aggregate sales CSV data."
    )
    parser.add_argument("--input", required=True, help="Raw input CSV file")
    parser.add_argument(
        "--output", required=True, help="Timestamped processed CSV file"
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.is_file():
        print(f"ERROR: Input file does not exist: {input_path}")
        return 1

    # Refuse to overwrite an existing output.
    if output_path.exists():
        print(f"ERROR: Output already exists: {output_path}")
        return 1

    totals = defaultdict(Decimal)
    counts = defaultdict(int)
    total_rows = 0
    invalid_rows = 0
    filtered_rows = 0
    valid_rows = 0

    try:
        with input_path.open("r", newline="", encoding="utf-8-sig") as source:
            reader = csv.DictReader(source)

            if reader.fieldnames != EXPECTED_HEADER:
                print(
                    "ERROR: Unexpected input header. Expected "
                    f"{EXPECTED_HEADER}, got {reader.fieldnames}"
                )
                return 1

            for row in reader:
                total_rows += 1

                try:
                    timestamp = row["timestamp"]
                    model = (row["model"] or "").strip()
                    sales_text = (row["sales"] or "").strip()

                    if not timestamp or not model or not sales_text:
                        raise ValueError("Missing required field")

                    if not MODEL_PATTERN.match(model):
                        filtered_rows += 1
                        continue

                    date = normalize_date(timestamp)
                    sales = Decimal(sales_text)

                    if not sales.is_finite():
                        raise ValueError("Sales value must be finite")

                    key = (date, model)
                    totals[key] += sales
                    counts[key] += 1
                    valid_rows += 1

                except (ValueError, InvalidOperation, TypeError) as exc:
                    invalid_rows += 1
                    print(
                        f"WARNING: Skipping CSV row {reader.line_num}: {exc}"
                    )

        # Exclusive creation avoids overwriting an existing result.
        # The file is written only after the input has been read.
        with output_path.open(
            "x", newline="", encoding="utf-8"
        ) as destination:
            writer = csv.writer(destination)
            writer.writerow(
                ["date", "model", "total_sales", "record_count"]
            )

            for (date, model), total in sorted(totals.items()):
                writer.writerow(
                    [date, model, format(total, "f"), counts[(date, model)]]
                )

    except FileExistsError:
        print(f"ERROR: Output already exists: {output_path}")
        return 1
    except (OSError, csv.Error) as exc:
        print(f"ERROR: Preprocessing failed: {exc}")
        return 1

    print(f"Input file: {input_path}")
    print(f"Output file: {output_path}")
    print(f"Total input rows: {total_rows}")
    print(f"Valid records aggregated: {valid_rows}")
    print(f"Filtered records: {filtered_rows}")
    print(f"Invalid records: {invalid_rows}")
    print(f"Output groups: {len(totals)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
