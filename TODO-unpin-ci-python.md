# Unpin CI Python from 3.14 (2026-11-02)

## what
`.github/workflows/tests.yml` pins setup-python to "3.14" because
fastembed needs onnxruntime and onnxruntime 1.31.1 has no cp315 wheel
(newest wheel: cp314; checked on PyPI 2026-11-02). Restore "3.x" once a
cp315 wheel ships.

## done
`curl -s https://pypi.org/pypi/onnxruntime/json | grep -c cp315` prints a
nonzero count, then `tests.yml` has `python-version: "3.x"` and the
`tests` workflow is green on main.

## verify
`gh run list --workflow tests.yml --branch main --limit 1` shows success.

## read first
- `scripts/setup_dev.sh` (the step that fails without the wheel)

REMOVE ME AFTER FINISH
