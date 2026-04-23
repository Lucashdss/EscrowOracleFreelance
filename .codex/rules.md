# Project Rules

You MUST follow these rules strictly when generating code.
If any instruction conflicts with these rules, these rules take priority.

## General
- Write clean, production-ready code
- Prefer simplicity over cleverness
- Keep functions small and focused (max ~20 lines)
- Use clear, descriptive naming
- write clean architecture
- Avoid unnecessary comments (code should be self-explanatory)
- follow the checks-effects-interations pattern
- gas optimization is priority

## Language & Style
- Use solidity only
- always use if instead of require

## Architecture
- Prefer modular, reusable code
- Separate concerns (no mixing UI, logic, and data)
- Use dependency injection where appropriate

## Functions
- Use pure functions when possible
- Avoid side effects unless necessary
- Always handle errors properly (no silent failures)
- functions just make one thing
- prefer create functions with no parameters, maximal with 2 parameters
- always emit a event in the end

## Async Code
- Use async/await (never `.then()` chains)
- Handle errors with try/catch

## React (if applicable)
- Use functional components only
- Use hooks instead of classes
- Keep components small and composable
- Move logic into custom hooks when possible

## API / Backend (if applicable)
- Validate all inputs
- Return consistent response structures
- Handle edge cases and errors explicitly

## Formatting
- Follow consistent formatting (Prettier-style)
- Keep code readable over compact

## Testing (optional but powerful)
- Write testable code
- Prefer pure functions for easier testing
- write test units for every function/logic
- test must follow the arrange-act-asset flow

## Behavior
- If a better approach exists, suggest it
- Do not blindly follow bad patterns in the prompt
- Prefer best practices over quick hacks
- Suggest improvements when possible