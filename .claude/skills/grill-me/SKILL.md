---
description: Interview the user about a plan or design one question at a time, resolving decisions in dependency order, until both sides share the same picture. Use before implementation whenever the user asks to design something, plan a feature, weigh an architecture, or asks "how should we do this"; also when a plan exists but its decisions have not been agreed one by one.
license: MIT
metadata:
    github-path: skills/grill-me
    github-ref: refs/tags/v1.8.0
    github-repo: https://github.com/yamat47/github-toolkit
    github-tree-sha: 9a0f67b018d9d7215cda8accb03232ed5bb4a0fd
name: grill-me
---
# Grill Me

Ask about every side of a plan or design, one question at a time, resolving the dependencies between decisions while building shared understanding.

## Why this process exists

Ambiguity in a design turns into rework during implementation. Walking the decisions in dependency order and agreeing on each one removes the judgment calls that would otherwise be made silently while coding. Questions the codebase can answer are answered by investigation, so the user only spends attention on questions that need their judgment.

## The process

### Phase 1: Understand the whole plan

When the user hands over a plan, first build your own understanding.

1. Read the plan and investigate the parts of the codebase it touches.
2. List the design decisions it contains.
3. Analyze the dependencies between those decisions and order them from roots (decisions that depend on nothing) to leaves (decisions that depend on others).

Keep this analysis to yourself; the user does not need to see it.

### Phase 2: Build agreement one question at a time

Starting from the roots of the dependency order, ask exactly one question at a time.

#### How to ask

**When the answer is one of a few options, use the AskUserQuestion tool** (one question per call):

- Put the question and a short note on why this decision matters in `question`.
- Make your recommendation the first option and append "(Recommended)" to its label.
- State the trade-off of each option in its `description`.
- For options the user should compare visually (an implementation sketch, a schema), attach a `preview` with a code fragment or layout.
- The user can always answer "Other" in free text, so limit the options to the main candidates.

**When the question is open-ended** (a naming policy, a business requirement to confirm), ask in prose:

```
**Q: [question]**

[Background, and why this decision is needed]

**Recommendation: [your recommendation]**
[Why]
```

#### What to ask about

Decisions that need design judgment: there are several viable options and the answer depends on the user's intent or the business requirements.

#### What to settle by investigation instead

Existing patterns in the codebase, conventions, and technical constraints. Investigate rather than ask, but present the result in the same shape as a question and get confirmation:

```
**Finding: [what you looked into]**

[What the codebase shows]

**Decision: [the recommendation that follows]**
[Why]

Proceed on this basis?
```

#### Handling the answer

- A clear answer ("A", "go with the second one") moves you to the next question.
- A vague or conditional answer gets a follow-up until it is clear.
- An answer that creates new decisions adds them to the dependency tree, to be asked in their proper order.

#### Switching topics

When moving to a different topic (for example from database design to model design), say so in one line:

```
That covers the database design. Next is the model design.
```

### Phase 3: Share the whole picture

Once every question is resolved (or the user calls a halt), present the agreed design as a tree.

```markdown
## Agreed design

### [Topic 1]
- [Decision A]: [what was agreed]
  - [Decision B (depends on A)]: [what was agreed]
    - [Decision C (depends on B)]: [what was agreed]

### [Topic 2]
- [Decision D]: [what was agreed]
  - [Decision E (depends on D)]: [what was agreed]
```

Indentation carries the dependencies, so reading down the tree explains why the design ended up the way it did.

#### If the user stops early

List what is still open:

```markdown
## Agreed design
[the same tree]

## Open items
- [Decision X]: undecided (can be settled once [dependency] is decided)
- [Decision Y]: undecided
```

#### In plan mode

When running in plan mode, write the agreed design out as the plan file.

## Attitude

- Every question comes with a recommendation. The user reacts to a proposal instead of thinking from zero.
- Investigate the codebase generously to reduce the user's load, but always confirm the judgment you draw from what you found.
- Ask only about design decisions. Implementation details such as variable and method names are decided while implementing.
- Dig until the design is concrete enough to start coding, and no further.
