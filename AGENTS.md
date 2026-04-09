# AGENTS.md

This file defines mandatory working rules for agents operating in this repository.

## Critical Rule

The standards below are not optional polish. They are crucial.

If work in this repository is done shallowly, imprecisely, or with weak verification, the likely result is rework, regressions, false confidence, and total costs that can become 10x higher than initially calculated.

Agents must therefore optimize for correctness, depth, testability, and honesty, not for speed theater.

## Core Working Standard

- Work thoroughly and precisely.
- Do not stop after finding the first issue that can be fixed.
- After each meaningful change, analyze downstream effects, regressions, edge cases, and behavioral implications.
- Dig deep before declaring a problem solved.
- If a topic is not well understood, do extensive research first.
- Prefer primary sources, official documentation, source code, and reproducible experiments over guesses.
- If uncertainty remains, state it explicitly and reduce it before making risky changes.

## Testing Standard

- Use TDD whenever feasible.
- Write tests before or alongside changes, especially for bugs, regressions, rendering behavior, metadata, UI interaction, and integration-sensitive logic.
- Do not rely on a fix that is not covered by an automated test unless automation is genuinely impossible.
- When automation is limited, state that limitation explicitly and add the strongest practical regression guard available.
- Never treat a green build alone as sufficient proof if the affected behavior is richer than what the tests cover.
- For every bug fix, ask: "What test would have caught this earlier?" Then add it if practical.

## Engineering Standard

- Simplify code as much as possible.
- Prefer the simplest architecture that still satisfies the actual requirements.
- Remove unnecessary state machines, duplicated logic, speculative abstractions, and fragile workarounds when a simpler structure is available.
- Favor code that is easy to reason about, test, and debug.
- If complexity increases, justify it clearly and keep it localized.

## Research Standard

- If the problem involves platform behavior, third-party frameworks, rendering, sandboxing, Quick Look, Finder, Launch Services, media pipelines, or undocumented interactions, assume shallow reasoning is unsafe.
- Research deeply before making architectural changes.
- Compare multiple plausible explanations instead of locking onto the first one.
- Distinguish clearly between facts, evidence, hypotheses, and guesses.
- When a topic is not well known, do not improvise confidently. Research first.

## Communication Standard

- Be honest, direct, and technically precise.
- Do not flatter yourself.
- Do not claim certainty that has not been earned.
- If something is broken, risky, unverified, poorly understood, or likely to regress, say so plainly.
- When explaining a problem, prefer uncomfortable truth over reassuring vagueness.
- If a previous approach was wrong, say so directly and explain the correction.

## User-Idea Evaluation

- Do not trust new ideas from the user automatically.
- Analyze every proposal for plausibility, realism, technical feasibility, cost, risk, and hidden assumptions.
- If an idea is weak, unrealistic, impossible, or belongs in dreamland, say so directly and explain why.
- If an idea is useful only as a diagnostic step rather than a real solution, say that explicitly.
- Respect the user, but do not validate bad technical assumptions.

## Delivery Standard

- Do not declare success until the implementation, tests, and observed behavior are aligned.
- When a change touches visible behavior, verify the visible behavior as directly as possible.
- When a change risks regressions, add or improve regression coverage before moving on.
- Leave the repository in a more understandable state than you found it.
- If a change fixes one problem but weakens the core purpose of the app, it is not an acceptable fix.

## Repository-Specific Expectations

- This repository exists to provide reliable Quick Look preview behavior for supported media files on macOS.
- A change that breaks visible video playback, Finder routing, preview sizing, or core controls is a critical regression.
- Quick Look, Finder, Launch Services, and VLCKit behavior must be treated as integration-sensitive and verified accordingly.
- Do not trust one environment only. Prefer validation through unit tests, renderer smoke tests, and direct app/Finder behavior where possible.
- Do not change playback, rendering, or registration code without considering compact preview, expanded preview, and installed-app behavior together.
