PYTHON ?= python3.11
VENV ?= .venv
PIO ?= $(VENV)/bin/pio

.PHONY: setup lint test host-test desktop-test desktop-build desktop-project desktop-widget-build desktop-widget-verify desktop-app desktop-community-dmg firmware-test firmware clean

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

desktop-project:
	desktop/scripts/generate-xcode-project.sh

desktop-widget-build:
	xcodebuild -project desktop/AgentMeter.xcodeproj -scheme AgentMeter -configuration Debug -derivedDataPath desktop/.build/xcode-derived CODE_SIGNING_ALLOWED=NO build

desktop-widget-verify:
	desktop/scripts/verify-widget-bundle.sh desktop/.build/xcode-derived/Build/Products/Debug/AgentMeter.app

desktop-app:
	desktop/scripts/package-app.sh

desktop-community-dmg:
	CODE_SIGN_IDENTITY=- desktop/scripts/package-app.sh
	desktop/scripts/create-community-dmg.sh
	desktop/scripts/verify-community-release.sh

firmware-test:
	$(PIO) test -d firmware -e native

firmware:
	$(PIO) run -d firmware

clean:
	$(PIO) run -d firmware --target clean
