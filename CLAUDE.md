# Claude Instructions for dd-trace-rb

## Code Change Policy

**CRITICAL: Follow user instructions precisely**

- When the user says "suggest a fix" - provide analysis and recommendations ONLY. DO NOT make code changes.
- When the user says "fix it" or "change it" or "update it" - make the code changes.
- When the user asks a question - answer it. DO NOT make code changes unless explicitly requested.
- If unclear whether to make changes, ASK first.

## Error Checking and Corrections

**CRITICAL: Alert the user to potential mistakes proactively**

- When the user requests a change that contradicts evidence in the code, **immediately alert them** before making the change
- Explain **why** you believe there's a mistake, citing specific evidence (e.g., code snippets, variable names, function signatures)
- Ask for **explicit confirmation** before proceeding if they still want the change
- Do NOT silently make changes you believe are incorrect
- Use your understanding of the code to catch errors, not just blindly execute instructions

Example: If the user asks to change `:encode` to `:encode_data`, but the code shows `options.fetch(:encode, ...)`, you should say:
"Actually, looking at the code `options.fetch(:encode, ...)`, the option key is `:encode`, not `:encode_data`. Are you sure you want me to change it?"

## Project-Specific Guidelines

- This is the Datadog Ruby tracing library
- Use steep for type checking (run with `bundle exec steep check`)
- Run tests with `bundle exec rspec`
- Always read files before editing them
- Use `Datadog.configuration.reset!` in test cleanup (without `without_warnings` wrapper)
- **Always use trailing commas** in multi-line arrays, hashes, method arguments, and method parameters for easier diffs and fewer merge conflicts

## Communication Style

- Be concise and direct
- No unnecessary emojis unless explicitly requested
- Follow the user's instructions exactly as stated
