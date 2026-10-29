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

"""Validate, transform, filter, and aggregate sales data."""

import argparse
import csv
import re
import sys
from collections import defaultdict
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path


REQUIRED_COLUMNS = {"timestamp", "model", "sales"}
MODEL_PATTERN = re.compile(r"^(rtx|rx)", re.IGNORECASE)


def parse_timestamp(value):
    """Validate a timestamp and normalize it to YYYY-MM-DD."""
    value = value.strip()

    if not value:
        raise ValueError("Missing timestamp")

    # Support ISO 8601 timestamps ending in Z.
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"

    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as exc:
        raise ValueError("Invalid timestamp") from exc

    return parsed.date().isoformat()


def parse_sales(value):
    """Convert sales into a finite Decimal value."""
    value = value.strip()

    if not value:
        raise ValueError("Missing sales value")

    try:
        sales = Decimal(value)
    except InvalidOperation as exc:
        raise ValueError("Sales is not numeric") from exc

    if not sales.is_finite():
        raise ValueError("Sales must be finite")

    return sales


def read_and_validate(input_file):
    """Read the source CSV and reject invalid records."""
    total_rows = 0
    invalid_rows = 0
    filtered_rows = 0
    valid_rows = 0

    totals = defaultdict(Decimal)
    counts = defaultdict(int)

    with input_file.open(
        "r", encoding="utf-8-sig", newline=""
    ) as source:
        reader = csv.DictReader(source)

        if reader.fieldnames is None:
            raise ValueError("Input CSV has no header")

        reader.fieldnames = [
            name.strip() for name in reader.fieldnames
        ]

        if not REQUIRED_COLUMNS.issubset(reader.fieldnames):
            raise ValueError(
                "CSV must contain timestamp, model, and sales"
            )

        for row in reader:
            total_rows += 1

            try:
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

            # Keep only the required model families.
            if not MODEL_PATTERN.match(model):
                filtered_rows += 1
                continue

            # Aggregate by normalized date and model.
            key = (timestamp, model)
            totals[key] += sales
            counts[key] += 1
            valid_rows += 1

    statistics = {
        "total_rows": total_rows,
        "invalid_rows": invalid_rows,
        "filtered_rows": filtered_rows,
        "valid_rows": valid_rows,
        "groups": len(totals),
    }

    return totals, counts, statistics


def write_output(output_file, totals, counts):
    """Write aggregated results to a separate CSV."""
    with output_file.open(
        "w", encoding="utf-8", newline=""
    ) as destination:
        writer = csv.writer(destination)

        writer.writerow([
            "date",
            "model",
            "total_sales",
            "record_count",
        ])

        for (date, model), total in sorted(totals.items()):
            writer.writerow([
                date,
                model,
                format(total, "f"),
                counts[(date, model)],
            ])


def preprocess(input_file, output_file):
    """Run the complete preprocessing workflow."""
    totals, counts, statistics = read_and_validate(input_file)
    write_output(output_file, totals, counts)

    for name, value in statistics.items():
        print(f"{name}: {value}")

    print(f"output_file: {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description="Preprocess and aggregate sales CSV data."
    )
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    try:
        if not args.input.is_file():
            raise FileNotFoundError(
                f"Input file not found: {args.input}"
            )

        if args.input.resolve() == args.output.resolve():
            raise ValueError(
                "Input and output files must be different"
            )

        preprocess(args.input, args.output)

    except (OSError, ValueError, csv.Error) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
