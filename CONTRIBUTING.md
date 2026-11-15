# Contributing to Glimpse

Thanks for helping. Glimpse is a small, native, MIT-licensed macOS menu-bar monitor. This guide covers how to propose a change and how we work, including with AI tools.

Start with [docs/architecture.md](docs/architecture.md) for how the code is organized, and [docs/design.md](docs/design.md) for why.

## Proposing a change

1. **Open an issue first** for new behaviour, describing the user need. Small fixes can go straight to a pull request.
2. **Branch from `main`**, keep the change focused, and match the existing style.
3. **Monitoring changes need evidence**: accuracy (how you compared readings) or overhead (see [docs/performance.md](docs/performance.md)).
4. **Keep the docs true**: update [docs/architecture.md](docs/architecture.md) when modules, data flow, threading, persistence, editions, scripts or the release pipeline change, and the user-facing docs when behaviour changes.
5. **Open a pull request.** CI must pass. Describe what you verified and what you couldn't (hardware, macOS 12, Intel, sleep/wake).

Ground rules:

- macOS 12 stays the deployment target; don't raise it for a convenience API.
- Native counters only: no shell commands or subprocess polling. Missing data is shown as unavailable, never zero.
- Independent implementation: don't copy code from GPL projects (such as iGlance) or Apple sample code with incompatible terms. SF Symbols may be used in the UI but never in the app icon or logos.
- Never commit secrets, certificates, signing keys, personal diagnostics, or paths and hostnames from your own machine.

## Requirements

- macOS with Xcode 27.2 (or its command-line tools) selected: `sudo xcode-select -s /Applications/Xcode.app`.
- Nothing else: SwiftPM fetches the pinned Sparkle framework. `make-dmg.sh` creates its own Python virtualenv for `dmgbuild`.

## Build, test and release

```bash
swift test                                   # all tests
./scripts/build-app.sh && open build/Glimpse.app
build/Glimpse.app/Contents/MacOS/Glimpse --diagnose
```

- Building, running, the Mac App Store edition and running the CI checks by hand: [docs/development.md](docs/development.md).
- Releases (maintainer only), including every step by hand: [docs/releasing.md](docs/releasing.md).

## AI guidelines

**How we use AI.** The maintainer builds Glimpse with AI coding agents (such as Claude Code and Codex). They write code, tests and docs, and measure performance. Every change still goes through `swift test`, CI and maintainer review. Agents never handle signing keys, credentials or releases; those steps stay with the maintainer. Agent-written commits carry a `Co-Authored-By` trailer.

**The rules agents follow** are in [AGENTS.md](AGENTS.md): constraints, build and verify commands, and which docs to keep current. Point your own agent at it.

**If you use AI in a contribution:**

- You are the author. Understand every line, run it, and be ready to explain it in review.
- Say so in the pull request when an AI tool wrote a substantial part, and keep any co-author trailer it adds.
- Back claims with evidence, not model output. Accuracy and performance claims need the comparison or measurement you ran.
- Licensing applies to generated code too. Don't submit output that reproduces GPL code (such as iGlance) or other incompatible sources.
- Don't paste private data into AI tools. Diagnostics and card renders can include local addresses and hostnames.
- Keep pull requests focused. Large generated rewrites, reformatting or speculative abstractions will be asked to shrink.
