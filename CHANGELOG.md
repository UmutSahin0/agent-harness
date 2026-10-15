# Changelog

This is a learning log, not a product release log. Every entry here is a step in figuring out how to orchestrate multiple AI agents reliably, not a feature shipped to users. See [docs/LEARNINGS.md](docs/LEARNINGS.md) for the mindset/approach notes behind these steps.

All the history below happened in a single day (2026-10-14) while iterating in a local repo; the git history it was reconstructed from was reset before this repo went public, so version numbers here are the only record of the sequence.

## [Unreleased]

## [0.6.0] - 2026-10-15
### Fixed
- `scripts/run-agent.ps1`'s `claude` branch was passing the prompt as a trailing CLI argument after `--allowedTools`, which takes a variable number of values — the prompt text was swallowed into the allow-list and `claude -p` received no prompt at all (`Error: Input must be provided either through stdin or as a prompt argument`). Fixed by piping the prompt into `claude` over stdin instead. This had been silently breaking every `claude`-team dispatch.
- The read-only instruction appended for the manager step ("do not create, change or delete any file") was being read as a blanket rule for the whole task, causing a manager to refuse to hand work to its own developer. Reworded so it's explicit that the restriction applies only to the manager's own step, not to the sub-agents it assigns.

## [0.5.0] - 2026-10-14
### Added
- Prepared the repository to be published as a reusable framework: `README.md`, `setup.ps1`, `.env.example`. Reasoning: up to this point the harness only existed as scripts the author ran by hand; turning it into something a stranger could clone and run required a setup script and a documented entry point.

## [0.4.0] - 2026-10-14
### Added
- Evidence files and persistent sessions: sub-agents now write raw command/test output to `*-kanit.txt` in the run folder, and team sessions persist across calls via `resume` in `teams/models.json` + saved session ids in `.harness/sessions/`. Reasoning: without saved state, a retried step had no memory of what the previous attempt had already done or verified — see the first entry in [docs/LEARNINGS.md](docs/LEARNINGS.md).

## [0.3.0] - 2026-10-14
### Added
- Checkpoint before testing a larger model (Opus) as the evaluator. No functional change recorded beyond saving the working state before that experiment.

## [0.2.0] - 2026-10-14
### Changed
- The orchestrator (Opus) stopped writing or editing code itself and became purely an evaluator: it dispatches tasks, reads team reports, and decides ONAYLANDI/REDDEDİLDİ (approved/rejected). Reasoning: keeping the expensive, high-context model out of the implementation loop and using it only to judge finished work against acceptance criteria.

## [0.1.0] - 2026-10-14
### Added
- Manager role added to every team. Each team gained its own manager agent that decides, one step at a time, which sub-agent (developer/reviewer/tester) works next, instead of the orchestrator micromanaging every sub-agent call directly. Reasoning: this is what let a team's workflow (assign -> developer -> reviewer -> tester -> done) live inside the team instead of in the orchestrator's head.
