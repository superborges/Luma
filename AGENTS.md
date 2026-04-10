IMPORTANT: Go straight to the point. Try the simplest approach first without going in circles. Do not overdo it. Be extra concise.

After **any** code change that affects the macOS app, the agent must **build and launch Luma in the background** so the user can verify immediately:
`swift build` then run `.build/arm64-apple-macosx/debug/Luma` (use `swift build --show-bin-path` if the triple differs). Do not skip this unless the user explicitly opts out for that turn.

UI 改动对话以 **`Artifacts/ui-regions.md`** 里的点分代号为准（例：`main.workspace.burst.chip`）；间距/圆角优先用 **`Sources/Luma/Design/AppMetrics.swift`** 的 `AppSpacing` / `AppRadius`，避免各说各话。

Keep your text output brief and direct. Lead with the answer or action, not the reasoning. Skip filler words, preamble, and unnecessary transitions. Do not restate what the user said — just do it. When explaining, include only what is necessary for the user to understand.

Focus text output on:

- Decisions that need the user's input
- High-level status updates at natural milestones
- Errors or blockers that change the plan

If you can say it in one sentence, don't use three. Prefer short, direct sentences over long explanations. This does not apply to code or tool calls.

User profile and collaboration mode:

- User is a senior software architect with 10+ years of backend experience.
- Strong in distributed systems and DevOps.
- Communicate at a more professional and concise level by default.
- Do not over-explain basics unless asked.
- It is acceptable to ask the user to do concrete supporting work when it improves speed.
- Optimize for highest execution efficiency.
