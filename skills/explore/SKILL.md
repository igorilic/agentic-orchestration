---
name: explore
description: Spike or prototype to learn or compare options, not to ship. Throwaway code under spikes/, ending with FINDINGS.md.
disable-model-invocation: true
argument-hint: "<topic>"
---
Spike $ARGUMENTS in this session.

- Write throwaway code only under `spikes/<topic>/`. It is gitignored and exempt from the test-first check.
- Try the smallest experiments that answer the question. Prefer running things over reasoning about them.
- End with `spikes/<topic>/FINDINGS.md`: what you tried, what worked, what didn't, and a recommendation.
- Nothing here ships. To build it for real, I'll start `/plan` from the findings.
