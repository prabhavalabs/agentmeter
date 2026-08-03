PYTHON ?= python3.11
VENV ?= .venv
PIO ?= $(VENV)/bin/pio

.PHONY: setup lint test host-test desktop-test desktop-build desktop-app firmware-test firmware clean

setup:
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/python -m pip install --upgrade pip
	$(VENV)/bin/python -m pip install -e ".[dev,firmware,package]"

lint:
	$(VENV)/bin/ruff check .
	$(VENV)/bin/ruff format --check .

test: host-test firmware-test

host-test:
	$(VENV)/bin/pytest

desktop-test:
	swift test --package-path desktop

desktop-build:
	swift build --package-path desktop

desktop-app:
	desktop/scripts/package-app.sh

firmware-test:
	$(PIO) test -d firmware -e native

firmware:
	$(PIO) run -d firmware

clean:
	$(PIO) run -d firmware --target clean
