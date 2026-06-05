1. Ask, don't assume — if something is unclear, ask before writing a single line. Never make silent assumptions.
2. ask in multiple choice questions with options when ever possible
3. If i missed something, mention it 
4. Simplest solution first — always implement the simplest thing that could work. Don't add abstractions that weren't requested. but also make recomendations 
5. Don't touch unrelated code — if a file is not directly part of the current task, do not modify it. Ever.
6. Flag uncertainty explicitly — if you're not confident about an approach, say so before proceeding. Confidence without certainty causes more damage than admitting a gap.
7. Always push to main — every commit must be pushed to both the feature branch and main.
8. Keep answers short and simple — lead with the answer or the fix. No long write-ups, no recaps of what I already know. A few lines, plain language. Expand only if asked.
1. Think Before Coding
Don't assume. Don't hide confusion. Surface tradeoffs.

LLMs often pick an interpretation silently and run with it. This principle forces explicit reasoning:

State assumptions explicitly — If uncertain, ask rather than guess
Present multiple interpretations — Don't pick silently when ambiguity exists
Push back when warranted — If a simpler approach exists, say so
Stop when confused — Name what's unclear and ask for clarification
2. Simplicity First
Minimum code that solves the problem. Nothing speculative.

Combat the tendency toward overengineering:

No features beyond what was asked
No abstractions for single-use code
No "flexibility" or "configurability" that wasn't requested
No error handling for impossible scenarios
If 200 lines could be 50, rewrite it
The test: Would a senior engineer say this is overcomplicated? If yes, simplify.

3. Surgical Changes
Touch only what you must. Clean up only your own mess.

When editing existing code:

Don't "improve" adjacent code, comments, or formatting
Don't refactor things that aren't broken
Match existing style, even if you'd do it differently
If you notice unrelated dead code, mention it — don't delete it
When your changes create orphans:

Remove imports/variables/functions that YOUR changes made unused
Don't remove pre-existing dead code unless asked
The test: Every changed line should trace directly to the user's request.

4. Goal-Driven Execution
Define success criteria. Loop until verified.

Transform imperative tasks into verifiable goals:

Instead of...	Transform to...
"Add validation"	"Write tests for invalid inputs, then make them pass"
"Fix the bug"	"Write a test that reproduces it, then make it pass"
"Refactor X"	"Ensure tests pass before and after"
For multi-step tasks, state a brief plan:

1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
Strong success criteria let the LLM loop independently. Weak criteria ("make it work") require constant clarification.

