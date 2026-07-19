# Contribution [#]: [Issue Title]

**Contribution Number:** [2]  
**Student:** [Alexandru VOicu]  
**Issue:** [[GitHub issue link](https://github.com/Nebulyn-Labs/MediFlow/issues/88)]  
**Status:** [Phase IV] [In Progress]

---

## Why I Chose This Issue

[1-2 paragraphs explaining why this issue interests you, how it matches your skills/learning goals, what you hope to learn]
This project is related to a medical program much like my first one, but in a smaller repo where I feel the codebase is easier to understand, and the maintainers are easier to contact. The issue itself is also relatively smaller, making me feel more confident in being able to solve it.
---

## Understanding the Issue

### Problem Description

[Currently, the logout behavior happens as soon as the button is pressed, but they would like to have a confirmation dialogue first where an accidental click doesn't fully stop the user.]

### Expected Behavior

[attempting to log out should have a confirmation pop up allowing the choice between confirming and logging out, or cancelling and returning to normal function]

### Current Behavior

[Clicking log out button instantly ceases the program]

### Affected Components

[the logout function, which has to files it pertains to within the facility and shared folders in lib. Both are .dart files]

---

## Reproduction Process

### Environment Setup

[Had to install flutter and dart to get everything set up, but ultimately wasn't hard to be able to reproduce as the program itself is a web app]

### Steps to Reproduce

1. [Be within the program]
2. [select the option to log out]
3. [the session terminates]

### Reproduction Evidence

- **Commit showing reproduction:** [[Link to commit in your fork](https://github.com/iroquoispliskin2/MediFlow-avfork/tree/fix/logout-confirmation)]
- **Screenshots/logs:** [If applicable]
- **My findings:** [What you discovered during reproduction]

---

## Solution Approach

### Analysis

[The logout function occuring without checking any flags first]

### Proposed Solution

[Creating a new function that will be inserted before the logout operation, and making sure the confirmation is first acquired before either returning out of the log out function or continuing with it and logging out]

### Implementation Plan

Using UMPIRE framework (adapted):

**Understand:** [Logout functions without confirmation, and we need to change this]

**Match:** [certain flags before other functions exist that we can mimic in style]

**Plan:** [Step-by-step implementation plan]
1. [sidebar_layout.dart and facility_overview.dart will have their logout behaviors modified]
2. [function _confirmLogout will be added to sidebar_layout.dart]
3. [flutter tests to make sure the code itself isnt broken and actual function tests to make sure everything passes smoothly]

**Implement:** [[Link to your branch/commits as you work](https://github.com/iroquoispliskin2/MediFlow-avfork/tree/fix/logout-confirmation)]

**Review:** [The PR Form had a guideline for criteria to follow, so I made sure I passed all their tests and met the requirements]

**Evaluate:** [If the pop-up appears, and can successfully either cancel out or confirm the log in]

---

## Testing Strategy

### Unit Tests

- [ ] Test case 1: [Description]
- [ ] Test case 2: [Description]
- [ ] Test case 3: [Description]

### Integration Tests

- [ ] Integration scenario 1
- [ ] Integration scenario 2

### Manual Testing

[What you tested manually and results]

---

## Implementation Notes

### Week [7] Progress

[The whole problem was tackled within this week, going through every phase and now waiting for merge]

### Week [Y] Progress

[Continue documenting as you work]

### Code Changes

- **Files modified:** [sidebar_layout.dart, facility_overview.dart]
- **Key commits:** [[Links to important commits](https://github.com/Nebulyn-Labs/MediFlow/commit/0cb46cfd6da60d59a6cc1b545f4d31b84e0635e1)]
- **Approach decisions:** [i chose a very simple approach as the problem itself is not complex. a basic box here that stays in line with the rest of the program is the most effective method]

---

## Pull Request

**PR Link:** [[GitHub PR URL when submitted](https://github.com/Nebulyn-Labs/MediFlow/pull/94)]

**PR Description:** [I am responding to issue #88, adding a confirmation dialogue before logout occurs, prompting a simple choice between cancelling the logout and returning to normal operation, or confirming and going through with it.

Fixes # (88)
Type of Change

    Bug fix (non-breaking change which fixes an issue)
    New feature (non-breaking change which adds functionality)
    Breaking change (fix or feature that would cause existing functionality
    to not work as expected)
    Documentation update
    Chore / code cleanup / dependency update

Verification & Checklist

Please run the following commands locally before submitting your PR and ensure
they pass with zero errors:

    dart format --output=none --set-exit-if-changed . (Code formatting)
    flutter analyze (Static analysis check - must be zero warnings)
    flutter test (Unit/widget tests)

Please also confirm:

    My code follows the style guidelines of this project
    I have performed a self-review of my own code
    I have commented my code, particularly in hard-to-understand areas
    I have made corresponding changes to the documentation
    My changes generate no new warnings
]

**Maintainer Feedback:**
- [Date]: [Summary of feedback received]
- [Date]: [How you addressed it]

**Status:** [Awaiting review]

---

## Learnings & Reflections

### Technical Skills Gained

[This is my first time utilizing flutter, but ultimately as long as you read documentation and get a little help from AI at roadblocks its not difficult to adapt]

### Challenges Overcome

[As with the previous codebase, coming to understand is was the difficulty. Once you have a grasp of what works how though, implementing a function isn't as bad]

### What I'd Do Differently Next Time

[try to pick a more robust problem as I build my understanding of open source contributing with easier ones]

---

## Resources Used

- [Link to helpful documentation]
- [Tutorial or Stack Overflow post that helped]
- [GitHub issues or discussions that helped]
