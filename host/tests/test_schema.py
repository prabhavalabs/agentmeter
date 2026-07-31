import json
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).parents[2]


def test_example_snapshot_matches_schema() -> None:
    schema = json.loads((ROOT / "schemas/device-snapshot-v1.schema.json").read_text())
    snapshot = json.loads((ROOT / "fixtures/device-snapshot-v1.json").read_text())

    Draft202012Validator.check_schema(schema)
    Draft202012Validator(schema).validate(snapshot)
