# Scratchpad

Scratch-first, local-first, native macOS Markdown workspace.

- Product spec: SPEC.md
- Agent rules: AGENTS.md
- Plan: IMPLEMENTATION_PLAN.md
- Full architecture: MASTER_CANON.md

## Build

    brew install xcodegen
    xcodegen
    xcodebuild -scheme Scratchpad -destination "platform=macOS" build
