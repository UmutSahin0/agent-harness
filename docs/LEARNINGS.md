# Learnings

This file is a running log of what I noticed while building this harness and how I thought about fixing it — approach and mindset, not code. It grows with every version in [CHANGELOG.md](../CHANGELOG.md); each entry below is tied to a version there. If you're looking for what changed, read the changelog; if you're looking for why it changed, read this.

## Sub-agents have no memory of their own retries

**Observation.** When a step failed and had to be retried, the agent doing the retry started from zero. It didn't know a previous attempt had already written half the code, or that a test had already been run and failed for a specific reason. It would re-derive the same plan, sometimes re-implement the same file from scratch.

**Why it hurt.** Retries are supposed to be cheaper than the original attempt — you already know what went wrong. Instead every retry cost as much as the first try, and sometimes undid work that was actually fine.

**How we approached it.** We stopped treating the model's context window as the place where progress lives. Progress now lives on disk: sub-agents write their raw test/command output to `*-kanit.txt` files in the run folder, and the prompt explicitly tells the next agent to read the run folder's reports and evidence files before doing anything, and not to redo work that's already done. Separately, teams got persistent CLI sessions (`resume: true` in `teams/models.json`, session ids saved under `.harness/sessions/`), so a team literally continues the same conversation across tasks instead of starting cold every time.

**Takeaway.** An agent's memory isn't in the model — it's wherever you decide to put it. If you don't write it down (session resume, or a file it's told to read), it doesn't exist for the next attempt.

## The reliability comes from the scripts, not the agents

**Observation.** Looking back at what actually made runs behave predictably, it wasn't a clever prompt — it was the plumbing: `dispatch.ps1` starting an isolated PowerShell window per team/task, `wait-reports.ps1` polling for a report file with a timeout instead of blocking forever, `close-sessions.ps1` giving a clean way to reset state, and `run-agent.ps1` being the single place that builds the CLI invocation and handles a failed resume by falling back to a fresh session.

**Why it hurt (when it wasn't there).** Early on, a bug in this plumbing (not in any agent's reasoning) was enough to break the entire pipeline — see the `--allowedTools` / prompt-swallowing bug and the read-only-instruction-leaking-to-sub-agents bug in the 0.6.0 changelog entry. Two small mistakes in a few lines of script silently stopped every team from doing any work, while the agents themselves were never at fault.

**How we approached it.** Keep the orchestration layer boring, small, and inspectable: one script per responsibility (dispatch / wait / close), state as plain files you can open and read (`.harness/runs/`, `.harness/sessions/`), and a manager loop that is just "ask for one JSON decision, act on it, repeat" rather than something clever. It looks primitive, but primitive things are easy to debug when something breaks — and something always breaks first in the plumbing, not in the model's reasoning.

**Takeaway.** In a multi-agent system, invest disproportionately in the un-glamorous glue code. That's where outages actually come from.

## The orchestrator judges, it doesn't implement

**Observation.** Early versions had the main session doing real work alongside the teams. It was tempting, since it's usually the most capable model in the room.

**Why it hurt.** When the same session both writes code and judges whether the code is good, there's no independent check — the orchestrator can rationalize its own work as done. It also meant the orchestrator was burning its own context on implementation detail instead of staying focused on the big picture across tasks.

**How we approached it.** `CLAUDE.md` now says explicitly: the orchestrator plans, dispatches, waits, reads team reports, and gives an ONAYLANDI/REDDEDİLDİ (approved/rejected) verdict with a reason per task. It does not run tests or write code itself (dispatch and wait-reports are the only commands it runs). The judgment call is made by reading what the team's own reviewer/tester already said, the same way a human lead would review a pull request instead of re-writing it.

**Takeaway.** Separating "the one who built it" from "the one who signs off on it" is worth doing even when both roles could technically be the same model.

## Evidence lives in a file, not in a sentence

**Observation.** A sub-agent's report can say "I tested this and it works" without that being true, or without it being checkable later.

**Why it hurt.** A report is a claim. Claims are cheap. If the orchestrator (or a human) has to trust the sentence "tests passed" with nothing behind it, the whole review step is theater.

**How we approached it.** `AGENTS.md` requires that the raw output of every test or verification command be saved to a `*-kanit.txt` ("evidence") file in the run folder, and that the report only summarize it and point to the file. A reviewer or the orchestrator can open that file and see the actual command and actual output, not a paraphrase of it.

**Takeaway.** "I did X" and "here is the file proving I did X" are different claims with very different trust levels. Make the second one cheap to produce and the review step becomes real.

## Open hypothesis: why is the reviewer role the one without session resume?

In `teams/models.json`, every role has `resume: true` except `reviewer`, which is `false` in all three teams. The plausible reason is that a reviewer should look at each piece of work fresh, without being anchored by its own earlier opinions in the same task — the same reason a code reviewer sometimes benefits from not having written the code themselves. But this wasn't written down anywhere as a deliberate design decision at the time, so I'm noting it here as a hypothesis, not a confirmed rationale.

## Open questions

- **Cost.** There's no tracking yet of how much a single task actually costs across manager + developer + reviewer + tester calls, especially when retries happen. This is probably the next thing worth measuring before scaling up task size or team count.
- **Running teams in parallel.** The current rule is "one task per team at a time" because sessions are shared and persistent. Is there a way to let a team work on independent tasks concurrently without the session state stepping on itself, or does that require per-task sessions instead of per-team ones?
- **Recovery from a bad manager decision.** If a manager assigns bad work and the step limit runs out, the only recourse right now is the orchestrator rewriting the task and dispatching again from scratch. Is there a cheaper way to resume mid-task with a corrected instruction instead of restarting the whole team loop?
- **How much of this generalizes beyond Windows/PowerShell.** The whole harness assumes PowerShell semantics (separate windows, `Start-Process`-style dispatch). It's unclear yet which parts of the design are genuinely platform-independent ideas and which are accidental PowerShell-isms.
- **Where the line is between "task file" and "code".** Task files are structured Markdown read by a model, not parsed by any script. At what point does a task file become complex enough that it should become an actual schema/config instead of prose a model has to interpret correctly every time?
