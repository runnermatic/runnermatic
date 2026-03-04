# Runnermatic Lab Notes

## Section 1: Repo structure — DONE
- All scripts, systemd unit, and workflow file created
- Initial commit: `48e9b5a`

## Section 2: PAT-based registration — DONE
- PAT updated with Self-hosted runners:Write permission
- `register-runner-with-pat.sh` uses `gh api` — outputs valid registration tokens
- Used for runner removal tokens during Section 7 rebuild

## Section 3: systemd multi-runner — DONE
- Unit installed at `/etc/systemd/system/github-runner@.service`
- `manage-runners.sh` supports: install-unit, start/stop N, start-all/stop-all, status
- All 4 runners confirmed active via `systemctl`

## Section 4: Create test repo — DONE
- `runnermatic/runner-test-repo` created (public)
- `runnermatic/runnermatic` also created for main project
- Workflow pushed to `.github/workflows/four-runners-test.yml`
- Note: had to enable `allows_public_repositories` on the Default runner group via API

## Section 5: App-based registration — DONE
- `generate-jwt.js` — RS256 JWT using Node.js built-in `crypto`, no npm
- `register-runner-with-app.sh` — sources `app.env`, generates JWT, gets install token, gets registration token
- Fix applied: `export GITHUB_APP_ID GITHUB_APP_PRIVATE_KEY_PATH` for child process visibility
- Verified: outputs valid registration tokens without using the PAT

## Section 6: Workflow test (PAT-registered runners) — DONE
- Triggered `four-runners-test.yml` via `gh workflow run`
- All 4 jobs ran in parallel on self-hosted runners
- Run 22652620251: conclusion=success

## Section 7: App-only rebuild and final test — DONE
- Stopped all 4 runners
- Removed all registrations using `config.sh remove` with PAT-sourced tokens
- Re-registered all 4 using `configure-runner.sh app N` (App-only, no PAT)
- Started all 4, verified online via API
- Triggered workflow again
- Run 22652664240: all 4 jobs succeeded, conclusion=success

## Key Findings
- Fine-grained PATs require explicit per-scope permissions; org admin does not imply runner or content access
- Default org runner group has `allows_public_repositories: false` — must enable for public repos
- App-based registration is the cleaner path: no PAT rotation concerns, scoped to installation
- PAT consolidated into `config/org.env` (standalone `.pat` file removed as unnecessary)
