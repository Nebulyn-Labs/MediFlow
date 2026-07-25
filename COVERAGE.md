#Test Coverage

MediFlow enforces a minimum test coverage baseline in CI to prevent regressions as the codebase grows.

## How it works

CI runs `flutter test --coverage`, producing `coverage/lcov.info`.
- `tool/check_coverage.sh` calculates total line coverage(lines hit/ lines found) from that report and compares it against the value stored in [`coverage_baseline.txt`](coverage_baseline.txt).
- If coverage drops below the baseline, the `Flutter CI` workflow fails.

## Curretnt baseline

See [`coverage_baseline.txt`](coverage_baseline.txt) for the current number.

## Running coverage locally

```bash
flutter test --coverage
bash tool/check_coverage.sh
```

