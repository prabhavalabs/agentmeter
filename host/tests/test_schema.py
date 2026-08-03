import json
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).parents[2]


def test_example_snapshot_matches_schema() -> None:
    schema = json.loads((ROOT / "schemas/device-snapshot-v1.schema.json").read_text())
    snapshot = json.loads((ROOT / "fixtures/device-snapshot-v1.json").read_text())

    Draft202012Validator.check_schema(schema)
    Draft202012Validator(schema).validate(snapshot)


def test_example_management_messages_match_schema() -> None:
    schema = json.loads((ROOT / "schemas/device-management-v1.schema.json").read_text())
    validator = Draft202012Validator(schema)

    Draft202012Validator.check_schema(schema)
    for fixture_name in (
        "device-management-patch-v1.json",
        "device-management-state-v1.json",
    ):
        document = json.loads((ROOT / "fixtures" / fixture_name).read_text())
        validator.validate(document)


def test_example_desktop_ipc_messages_match_schema() -> None:
    schema = json.loads((ROOT / "schemas/desktop-ipc-v1.schema.json").read_text())
    validator = Draft202012Validator(schema)

    Draft202012Validator.check_schema(schema)
    for fixture_name in (
        "desktop-ipc-status-v1.json",
        "desktop-ipc-event-v1.json",
        "desktop-ipc-settings-v1.json",
        "desktop-ipc-error-v1.json",
    ):
        document = json.loads((ROOT / "fixtures" / fixture_name).read_text())
        validator.validate(document)
