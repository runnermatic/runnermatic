# Runnermatic Lab Notes

## Section 1: Repo structure — DONE
- All scripts, systemd unit, and workflow file created
- Initial commit: `48e9b5a`

## Section 2: PAT-based registration — SKIPPED (PAT lacks permissions)
- The fine-grained PAT does not have "Self-hosted runners: Write" org permission
- 403 on `/orgs/runnermatic/actions/runners/registration-token`
- Runners were registered via App mode instead (Section 5)

## Section 3: systemd multi-runner — DONE
- Unit installed at `/etc/systemd/system/github-runner@.service`
- All 4 runners started and verified online via App token API check
- `systemctl is-active` confirms all 4 active

## Section 5: App-based registration — DONE
- `generate-jwt.js` working (RS256, built-in crypto, no npm)
- `register-runner-with-app.sh` working — gets installation token then registration token
- Fixed: needed `export GITHUB_APP_ID GITHUB_APP_PRIVATE_KEY_PATH` for child process
- All 4 runners registered via App mode using `configure-runner.sh app N`
- Verified all 4 online: runnermatic-1 through runnermatic-4

## Section 4: Create test repo — BLOCKED
- PAT cannot create repos in org: "does not have the correct permissions to execute CreateRepository"
- Need PAT updated with org permissions:
  - **Administration: Write** (repo creation)
  - **Self-hosted runners: Write** (PAT registration path)

## Section 6: Workflow test — BLOCKED (needs Section 4)

## Section 7: App-only rebuild — BLOCKED (needs Section 6)
- However, runners are ALREADY registered via App-only, so the re-registration
  step is effectively already proven

## Ralph Loop Status — STALLED (iteration 10)
- Blocked since iteration 3 on PAT permissions
- Two PATs exist:
  - `gh auth token`: `github_pat_11AAATR7Q0hL1DMJ...` — can see org, cannot manage runners or create repos
  - `config/runnermatic-admin.pat`: `github_pat_11AAATR7Q0Zihsis...` — appears invalid (returns null user)
- To resume: update PAT with Administration:Write + Self-hosted runners:Write org permissions, then re-run Ralph loop
