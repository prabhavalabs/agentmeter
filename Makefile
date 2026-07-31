PYTHON ?= python3.11
VENV ?= .venv
PIO ?= $(VENV)/bin/pio

.PHONY: setup lint test firmware clean

setup:
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/python -m pip install --upgrade pip
	$(VENV)/bin/python -m pip install -e ".[dev,firmware]"

lint:
	$(VENV)/bin/ruff check .
	$(VENV)/bin/ruff format --check .

test:
	$(VENV)/bin/pytest

firmware:
	$(PIO) run -d firmware

clean:
	$(PIO) run -d firmware --target clean
