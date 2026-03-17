# Task: Baseline enforcement and lint coverage improvements

## Steps
- [x] Fix `compare-baseline.py`: fail when violation count decreases (enforce regeneration)
- [x] Fix `lint-yaml.sh`: include `.github/actions/**/*.yml` in scan (not just workflows)
- [x] Fix `lint-yaml.sh`: correct broken PATTERN regex (rule is at end of parsable line, not after `[level]`)
- [x] Fix all three lint scripts: delete baseline file when `--update-baseline` produces empty results
- [x] Fix `compare-baseline.py`: handle missing baseline file (treat as empty `{}`)
- [x] Regenerate all baselines with updated scripts
- [ ] Fix yamllint violations in `.github/actions/build-php-images/action.yml` (colons alignment)
- [ ] Fix yamllint violation in `.github/actions/preseed-downloads/action.yml` (empty-lines)

## Definition of Done
- `compare-baseline.py` fails on both increases and decreases from baseline.
- `lint-yaml.sh` scans all files under `.github/` (workflows + composite actions).
- Baseline files are deleted (not written as `{}`) when violation count reaches zero.
- All three lint checks pass in CI.
- Yamllint violations in action files are either fixed or tracked in the baseline.
