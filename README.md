<div align="center">

# 🧪 Agent Harness

**Orchestrating multiple AI agents: framework, scripts, and experiments.**

![Status](https://img.shields.io/badge/status-experimental-orange)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20PowerShell-blue)
![License](https://img.shields.io/badge/license-MIT-green)

[Medium](https://medium.com/@umutsahinn1) · [LinkedIn](https://www.linkedin.com/in/umutsahinn1/) · [Changelog](CHANGELOG.md) · [Learnings](docs/LEARNINGS.md)

</div>

---

> **This repository is not a product.**
> It is a playground where I poke at multi-agent orchestration, break things, notice why they broke, and write that down. Expect rough edges, Turkish strings in scripts and logs, and design decisions I may reverse next week. If it's useful as a reference, great. If you need something production-ready, this isn't it.

The interesting part is not the code, it's the **log of what went wrong and what I noticed**. Start with [docs/LEARNINGS.md](docs/LEARNINGS.md) and [CHANGELOG.md](CHANGELOG.md).

## Contents

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Setup](#setup)
- [Quick start](#quick-start)
- [Task file format](#task-file-format)
- [Report format](#report-format)
- [Repository layout](#repository-layout)
- [Configuration](#configuration)
- [Persistent sessions & resume](#persistent-sessions--resume)
- [Troubleshooting](#troubleshooting)
- [Learning log](#learning-log)
- [License](#license)

## How it works

One interactive **orchestrator** session (a Claude session guided by [CLAUDE.md](CLAUDE.md)) splits a request into tasks, writes one task file per task, and hands each task to a **team**. Each team has its own **manager** that decides, one step at a time, which sub-agent (**developer**, **reviewer**, **tester**) works next. The orchestrator never writes code itself: it dispatches, waits, and reads reports.

```
user
  │
  ▼
orchestrator (CLAUDE.md) ── writes .harness/tasks/T<n>.md
  │
  │  scripts/dispatch.ps1 -Team <claude|codex|cursor> -TaskFile ...
  ▼
team-manager.ps1 loop      (own PowerShell window, at most -MaxSteps steps)
  │
  ├─► manager    read-only, answers with ONE JSON object per step
  │     {"action":"assign","role":"developer","instruction":"...","reason":"..."}
  │     {"action":"done","status":"OK|SORUNLU","summary":"..."}
  │
  └─► developer ─► reviewer ─► tester      (fix rounds go back to developer)
  │
  ▼
.harness/reports/T<n>-<team>.md   ◄── scripts/wait-reports.ps1 polls for this
```

Every agent call goes through [scripts/run-agent.ps1](scripts/run-agent.ps1). It builds the prompt ("read your role file and your instruction file, then act"), picks the model from [teams/models.json](teams/models.json), and calls the team's CLI.

The standard flow (`developer → reviewer → tester → done`) is described in each `teams/<team>/roles/manager.md`. It is a **prompt convention**, not something the scripts enforce. The scripts only enforce that the manager picks a role that exists in `teams/<team>/roles/`.

## Requirements

| Need | Details |
|------|---------|
| **OS** | Windows with PowerShell 5.1+. The scripts are `.ps1` files and `dispatch.ps1` opens a new `powershell.exe` window. Not written for, or tested on, macOS/Linux. |
| **`claude` team** | `claude` CLI (Claude Code), installed and logged in, run as `claude -p` |
| **`codex` team** | `codex` CLI, installed and logged in, run as `codex exec` |
| **`cursor` team** | Cursor's `agent` CLI, installed and logged in, run with `-p` |

You only need the CLIs of the teams you actually dispatch to. The scripts do not log in for you.

> `setup.ps1` also checks for `python` on your `PATH` and exits if it's missing, even though no harness script uses Python (see below).

## Setup

From the repository root, in PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

What `setup.ps1` actually does (one switch: `-Force`):

1. Runs `python --version` and **exits with an error if Python is not found**.
2. Creates `.harness\tasks`, `.harness\reports`, `.harness\runs`, `.harness\sessions` if missing.
3. Copies `.env.example` to `.env` if `.env` doesn't exist.
4. Offers `pip install -r requirements.txt` if that file exists (it doesn't in this repo; `-Force` skips the question).
5. Checks that `dispatch.ps1`, `wait-reports.ps1` and `close-sessions.ps1` exist and prints next steps.

**Honest notes**

- **`.env` is not read by any script.** Only `setup.ps1` copies it. Authentication is whatever your installed CLIs already have. You can ignore `.env` and `.env.example`.
- The Python check and the `.env` / `requirements.txt` steps are leftovers. If you'd rather skip the script, just create the four `.harness` folders yourself.

## Quick start

**1. Write a task file** in `.harness/tasks/`, e.g. `T1.md` (format [below](#task-file-format)). The file name without extension is the task ID.

**2. Dispatch it.** Returns immediately; the team works in a separate window.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/dispatch.ps1 -Team claude -TaskFile .harness/tasks/T1.md
```

`-Team` is `claude`, `codex` or `cursor`. `-MaxSteps` (default `8`) limits the manager loop.

**3. Wait for the report.** Blocks up to `-TimeoutSec` seconds (default `540`), checking every 15 s. Prints one line per report, or `HALA CALISIYOR` ("still running"): run it again.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/wait-reports.ps1 -Reports T1-claude
```

`-Reports` is comma-separated, e.g. `T1-claude,T2-codex`.

**4. Read the report** at `.harness/reports/T1-claude.md`, and the run folder it names for per-step outputs and evidence.

**5. Close the persistent sessions** when you're completely done:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/close-sessions.ps1
```

Two conventions from `CLAUDE.md` (not enforced by the scripts): parallel tasks should have non-overlapping scopes, and a team should only get one task at a time because its sessions are shared.

## Task file format

Plain Markdown that the manager and sub-agents read. No script parses it; this structure is just the convention:

```markdown
# T<n>: <title>
Ekip: <codex|cursor|claude>
Amaç: ...
Kapsam: <exact folders/files; no placeholders>
Kabul kriterleri:
- measurable, testable items; spell out edge cases
Bağlam: interfaces with other tasks (function signatures, file formats, ...)
```

Field names are Turkish because the harness prompts are Turkish:

| Field | Meaning |
|-------|---------|
| `Ekip` | team |
| `Amaç` | goal |
| `Kapsam` | scope |
| `Kabul kriterleri` | acceptance criteria |
| `Bağlam` | context |

Pick an unused ID by looking at the existing files in `.harness/tasks/`.

## Report format

**Team report.** When the manager loop ends, `team-manager.ps1` writes `.harness/reports/T<n>-<team>.md`:

```
# T<n> - <team> ekibi raporu
Durum: OK | SORUNLU          (OK | PROBLEMATIC)
Ozet: <manager's summary>
Calisma klasoru: <run folder>

<history: one section per step with instruction, reason, result, output file>
```

If the step limit is reached before the manager finishes, the status is `SORUNLU` with "Adim limiti doldu" ("step limit reached"). `dispatch.ps1` deletes any old report for the same ID and team first, so a stale report can't be mistaken for a new one.

**Sub-agent report.** Defined in [AGENTS.md](AGENTS.md): `Değişen dosyalar`, `Yapılanlar`, `Kabul kriterleri` (each `[x]` / `[ ]`), `Notlar / riskler`, and a last line `DURUM: OK | SORUNLU`. Raw command output goes to `NN-<role>-kanit.txt` ("kanıt" = evidence) in the run folder.

## Repository layout

```
CLAUDE.md                orchestrator rules (interactive main session only)
AGENTS.md                rules for all team workers + report format
setup.ps1                optional setup helper
.env.example             copied to .env by setup.ps1; not read by any script
scripts/
  dispatch.ps1           start a team on a task in a new PowerShell window
  team-manager.ps1       the manager loop for one task/team
  run-agent.ps1          one agent call (model, session, CLI invocation)
  wait-reports.ps1       wait for / summarise reports
  close-sessions.ps1     delete saved session ids
teams/
  models.json            model / effort / resume per team and role
  claude|codex|cursor/roles/{manager,developer,reviewer,tester}.md
docs/
  LEARNINGS.md           what I noticed, as approach and mindset (no code)
.harness/
  tasks/                 your task files (T<n>.md), git-ignored
  reports/  runs/  sessions/   local experiment output, git-ignored (folders kept via .gitkeep)
CHANGELOG.md             step-by-step learning log
```

## Configuration

`teams/models.json` has one object per team (`claude`, `codex`, `cursor`), each with one object per role (`manager`, `developer`, `reviewer`, `tester`). Every role has three fields:

| Field | Meaning |
|-------|---------|
| `model` | Passed to the team's CLI (`--model` for `claude` and `cursor`, `-m` for `codex`). Empty means the CLI default. |
| `effort` | Reasoning effort. **Only `codex` uses it** (`-c model_reasoning_effort=<value>`). For `claude` and `cursor` it is read but not passed on. |
| `resume` | `true` keeps a persistent session for that team and role; `false` starts fresh each call. |

Current values: `claude` → `opus` (manager), `sonnet` (developer), `haiku` (reviewer, tester). `codex` → `gpt-6-luna` everywhere. `cursor` → `claude-haiku-5-5-low` everywhere. All `effort: low`. `resume` is `true` except `reviewer`, which is `false` in every team. Change the model names to whatever your CLIs and accounts support.

**Permissions set in `run-agent.ps1`**

- The manager runs read-only. `claude`: `--allowedTools Read,Grep,Glob`. `cursor`: no `--force`. `codex`: no read-only flag, the restriction is only in the prompt.
- Non-manager `claude` agents: `--permission-mode acceptEdits --allowedTools Bash`.
- `codex` agents run with `--dangerously-bypass-approvals-and-sandbox`; `cursor` agents with `--trust` and `--force`.

> ⚠️ Worker agents can edit files and run commands without approval prompts. Only run this on a repo and machine where you're comfortable with that.

## Persistent sessions & resume

With `"resume": true`, `run-agent.ps1` stores the CLI session id in `.harness/sessions/<team>-<role>.txt` and reuses it on the next call (`claude --resume`, `codex exec resume`, `agent --resume`). That is why teams remember earlier tasks. The prompt also tells the agent to read the run folder's reports and `*-kanit.txt` files if its memory is empty.

If resuming fails (non-zero exit), the session file is removed and one fresh session starts automatically. `close-sessions.ps1` deletes all `.harness/sessions/*.txt` and logs how many it closed.

## Troubleshooting

| Symptom | What to check |
|---------|---------------|
| Report never appears, `HALA CALISIYOR` keeps coming back | Look at the team's PowerShell window. Per-agent errors are in the `.log` next to each step output in `.harness/runs/T<n>-<team>-<timestamp>/`. |
| Manager errors immediately (exit code 1) | CLI not installed, not on `PATH`, not logged in, or the model name in `teams/models.json` isn't available to your account. Run the CLI by hand once. |
| `manager gecerli JSON dondurmedi` | The manager must answer with a single JSON object; otherwise the step is retried. Repeated failures burn through `-MaxSteps`. |
| Report `SORUNLU` with `Adim limiti doldu` | Raise `-MaxSteps` on `dispatch.ps1` or split the task. |
| `setup.ps1` says Python is required | The harness doesn't need Python. Create the four `.harness` folders by hand and skip the script. |
| Stale or broken sessions | Run `scripts/close-sessions.ps1`. |
| Turkish output | Logs, prompts and some status words are Turkish (`BASLATILDI` = started, `SORUNLU` = problematic). Intentional for now. |

## Learning log

- 📜 [CHANGELOG.md](CHANGELOG.md): what changed in each step, and why.
- 🧠 [docs/LEARNINGS.md](docs/LEARNINGS.md): what I noticed, in prose, no code.

## License

MIT. See [LICENSE](LICENSE).
