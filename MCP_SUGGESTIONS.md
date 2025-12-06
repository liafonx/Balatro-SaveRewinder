# Recommended MCP Tools for Balatro Modding

Given the Lua-based Love2D architecture of Balatro and the specific challenges of state management and hooking, the following Model Context Protocol (MCP) servers would be highly effective:

## 1. Lua Language Server (Static Analysis)
*   **Why:** Balatro modding involves dynamic typing and monkey patching (`lovely.toml`). A Lua Language Server MCP would allow the agent to:
    *   Analyze global variable usage (`G.GAME`, `G.STATE`).
    *   Detect undefined variables or signature mismatches in hooks.
    *   Provide "Go to Definition" capabilities across the injected code and the base game source (if indexed).
*   **Implementation:** Wrapper around `lua-language-server` that exposes diagnostics and symbol lookups via MCP resources/tools.

## 2. Balatro "Codebase Knowledge" Server (Documentation/Search)
*   **Why:** The game's source code (`balatro_src`) is proprietary and unindexed. A specialized MCP that:
    *   Indexes `balatro_src` (ignoring assets).
    *   Provides semantic search for game logic (e.g., "Where is the shop reroll cost calculated?").
    *   Maps `G.*` globals to their definitions and usages.
*   **Benefit:** Drastically reduces the time spent `grep`ing for game logic (like I had to do for `Card:open`).

## 3. Runtime Inspector / Debug Bridge
*   **Why:** The hardest part is understanding the *runtime* state (e.g., "What is `G.STATE` exactly when the save triggers?").
*   **Concept:** An MCP server that connects to a debug socket in the running Love2D instance (using `mobdebug` or similar).
*   **Capabilities:**
    *   `read_global(path)`: detailed dump of `G.pack_cards` or `G.GAME`.
    *   `listen_event(name)`: stream game events back to the LLM.
    *   `eval_lua(code)`: execute checks dynamically.
*   **Relevance:** This would have instantly solved the "unreliable heuristic" problem by allowing us to query the exact state during the save event.

## 4. Lovely Injector Validator
*   **Why:** `lovely.toml` relies on regex and pattern matching. If the game updates, patterns break.
*   **Tool:** An MCP tool that takes a `lovely.toml` pattern and the target file, verifying *exactly* where it matches and what the resulting code looks like.
