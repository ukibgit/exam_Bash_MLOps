"""
-------------------------------------------------------------------------------
This script runs the training of an XGBoost model to predict graphics card sales 
from the preprocessed data.

1. It starts by searching for the latest preprocessed CSV file in the 'data/processed/' directory.
2. If a standard model (model.pkl) does not exist, it loads the data, splits it into training and test sets, trains a model on this data, evaluates i>
3. If a standard model already exists, it trains a new model on the latest data, evaluates it, and saves the model in the 'model/' folder in the form>
4. Performance metrics (RMSE, MAE, R²) are displayed and saved in the log file.
5. Any errors are handled and reported in the logs.

The models are saved in the 'model/' folder with the name 'model.pkl' for the standard model and with a timestamp for later versions.
The model metrics are recorded in the script’s log files.
-------------------------------------------------------------------------------
"""


import logging
import sys
from datetime import datetime
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from xgboost import XGBRegressor
from sklearn.compose import ColumnTransformer
from sklearn.metrics import (
    mean_absolute_error,
    mean_squared_error,
    r2_score,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder


# Project paths
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data" / "processed"
MODEL_DIR = BASE_DIR / "model"
STANDARD_MODEL = MODEL_DIR / "model.pkl"


def train(data):
    """Train and evaluate an XGBoost GPU sales prediction model."""

    features = [
        "model",
        "day_of_week",
        "month",
        "day_of_month",
        "record_count",
    ]

    target = "total_sales"

    # Chronological train/test split
    dates = sorted(data["date"].unique())

    if len(dates) < 2:
        raise ValueError("At least two distinct dates are required.")

    split_index = max(1, int(len(dates) * 0.8))
    split_index = min(split_index, len(dates) - 1)
    split_date = dates[split_index]

    train_data = data[data["date"] < split_date]
    test_data = data[data["date"] >= split_date]

    if train_data.empty or test_data.empty:
        raise ValueError("Training or test data is empty.")

    X_train = train_data[features]
    y_train = train_data[target]

    X_test = test_data[features]
    y_test = test_data[target]

    # Encode GPU model names
    preprocessing = ColumnTransformer(
        transformers=[
            (
                "gpu_model",
                OneHotEncoder(handle_unknown="ignore"),
                ["model"],
            ),
        ],
        remainder="passthrough",
    )

    model = Pipeline([
        ("preprocessing", preprocessing),
        ("regressor", XGBRegressor(
            objective="reg:squarederror",
            n_estimators=200,
            max_depth=4,
            learning_rate=0.05,
            random_state=42,
        )),
    ])

    model.fit(X_train, y_train)

    # Evaluate model
    predictions = model.predict(X_test)

    rmse = np.sqrt(mean_squared_error(y_test, predictions))
    mae = mean_absolute_error(y_test, predictions)
    r2 = r2_score(y_test, predictions)

    logging.info("Model evaluation:")
    logging.info("RMSE: %.4f", rmse)
    logging.info("MAE: %.4f", mae)
    logging.info("R2: %.4f", r2)

    return model


def main():
    """Load processed data, train model and save the result."""

    try:
        logging.info("Starting GPU sales model training.")

        # Find latest processed CSV
        files = list(DATA_DIR.glob("sales_processed_*.csv"))

        if not files:
            raise FileNotFoundError(
                f"No processed CSV files found in {DATA_DIR}"
            )

        latest_file = max(files, key=lambda file: file.name)

        logging.info("Using processed file: %s", latest_file)

        # Load data
        data = pd.read_csv(latest_file)

        required_columns = {
            "date", "model", "total_sales", "record_count"
        }

        if not required_columns.issubset(data.columns):
            raise ValueError("Processed CSV is missing required columns.")

        data["date"] = pd.to_datetime(data["date"], errors="coerce")
        data["total_sales"] = pd.to_numeric(
            data["total_sales"], errors="coerce"
        )
        data["record_count"] = pd.to_numeric(
            data["record_count"], errors="coerce"
        )

        data = data.dropna(
            subset=[
                "date", "model", "total_sales", "record_count"
            ]
        ).copy()

        if data.empty:
            raise ValueError("No valid records available for training.")

        if (data["total_sales"] < 0).any():
            raise ValueError("Sales cannot be negative.")

        # Create date features
        data["day_of_week"] = data["date"].dt.dayofweek
        data["month"] = data["date"].dt.month
        data["day_of_month"] = data["date"].dt.day

        # Train and evaluate
        model = train(data)

        # Save model
        MODEL_DIR.mkdir(parents=True, exist_ok=True)

        if not STANDARD_MODEL.exists():
            model_path = STANDARD_MODEL
        else:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            model_path = MODEL_DIR / f"model_{timestamp}.pkl"

        joblib.dump(model, model_path)

        logging.info("Model saved successfully: %s", model_path)
        logging.info("GPU sales model training completed.")

        return 0

    except Exception:
        logging.exception("Error during model training.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
