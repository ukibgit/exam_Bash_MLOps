.PHONY: bash tests all

# preprocessed.sh is invoked automatically by collect.sh
bash:
	@echo "Starting GPU sales MLOps pipeline..."
	bash scripts/collect.sh
	bash scripts/train.sh


tests:
	pytest tests/test_collect.py && \
	pytest tests/test_preprocessed.py && \
	pytest tests/test_model.py

all: bash tests