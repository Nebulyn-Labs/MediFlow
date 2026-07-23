# Contributing to MediFlow

Thank you for your interest in contributing to MediFlow! We welcome
contributions from developers of all skill levels to help engineer a smarter,
healthier medical supply chain.

> New here? Check out the [Project Overview](README.md#project-overview) and
> [Tech Stack](README.md#tech-stack) in the README first to get familiar with
> the codebase.

Please read this document carefully before making changes. It outlines our
development setup, branch naming conventions, coding standards, testing
guidelines, and the pull request process.

Join our [Discord server](https://discord.gg/B4Z8MKmzcz) to ask questions,
discuss ideas, and connect with other contributors!

---

## Table of Contents

1. [Code of Conduct](#1-code-of-conduct)
2. [Setting Up Your Local Environment](#2-setting-up-your-local-environment)
3. [Claiming and Creating Issues](#3-claiming-and-creating-issues)
4. [Branch Naming Conventions](#4-branch-naming-conventions)
5. [Coding Standards & Conventions](#5-coding-standards--conventions)
6. [Testing](#6-testing)
7. [The Pull Request Process](#7-the-pull-request-process)

---

## 1. Code of Conduct

By participating in this project, you agree to abide by our
[Code of Conduct](CODE_OF_CONDUCT.md).

---

## 2. Setting Up Your Local Environment

### Flutter Installation

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) for
   your operating system.
2. Ensure you have the stable channel of Flutter (version `3.41.x` is
   recommended).
3. Verify your installation by running:

```bash
   flutter doctor
```

### Local Project Setup

1. **Star the Repository:**
   Before you start, please **⭐ star the repository ⭐** on GitHub to show
   your support!
2. **Fork and Clone:**
   Fork the repository on GitHub and clone your fork locally:

```bash
   git clone https://github.com/your-username/MediFlow.git
   cd MediFlow
```

3. **Add Upstream Remote:**
   Add the original repository as an upstream remote to keep your fork synced:

```bash
   git remote add upstream https://github.com/Nebulyn-Labs/MediFlow.git
```

4. **Fetch Packages:**

```bash
   flutter pub get
```

5. **Configure Environment Variables:**
   Create a `.env` file in the root of the project:

```ini
   GEMINI_API_KEY=your_gemini_api_key_here
   ORS_API_KEY=your_openroute_service_key_here
   FIREBASE_PROJECT_ID=mediflow-92e6f
```

   *Note: If you do not have API keys, you can use placeholder values like
   `dummy_key`. The application will still compile but some online features
   will be disabled.*

### Firebase Configuration

If you plan to modify or deploy Cloud Functions or Firestore rules:

1. Install the [Firebase CLI](https://firebase.google.com/docs/cli):

```bash
   npm install -g firebase-tools
```

2. Log in and select the project:

```bash
   firebase login
   firebase use mediflow-92e6f
```

---

## 3. Claiming and Creating Issues

Before working on any changes:

1. **Find an Issue:** Look at our GitHub Issue Tracker. Issues marked as
   `good first issue` are great starting points.
2. **Claim It:** Comment on the issue to request assignment. **Do not start
   work or open a PR until a maintainer assigns it to you** to avoid duplicate
   work. PRs without prior assignment may be closed.
3. **Open a New Issue:** If you want to work on something not currently on the
   tracker, open a `feature_request` or `bug_report` issue first to discuss it
   with the maintainers.
4. **Inactive Issues:** If an assigned issue has no meaningful updates for 7
   days, it may be unassigned to allow others to work on it. If you need more
   time, just leave a comment with a progress update.
5. **Issue Limit:** Contributors can be assigned to a maximum of 4 open
   issues at a time. If you are already at the limit, an assignment bot will
   automatically unassign you from any new issue and leave a comment
   explaining why. Finish or hand back one of your current issues to free up
   a slot.

---

## 4. Branch Naming Conventions

Always create a new branch for your work. Do not work directly on `main`. Use
the following naming convention:

- **Bug fixes:** `fix/issue-number-short-description` (e.g.,
  `fix/102-fix-login-overflow`)
- **Features:** `feature/issue-number-short-description` (e.g.,
  `feature/54-add-dark-mode`)
- **Documentation:** `docs/short-description` (e.g., `docs/update-readme`)
- **CI/CD or Build Tasks:** `chore/short-description` (e.g.,
  `chore/bump-version`)

---

## 5. Coding Standards & Conventions

### Coding Style

- Follow the official [Effective Dart Guide](https://dart.dev/guides/language/effective-dart)
  for styling guidelines.
- Always write clean, self-documenting code. Preserve existing comments and
  docstrings where possible.

### Linting and Formatting

Before committing your changes, you **must** ensure the code passes format
checks and static analysis.

1. **Format Code:**
   Ensure all Dart files are formatted correctly using the standard formatter:

```bash
   dart format .
```

2. **Run Static Analysis:**
   Ensure there are zero warnings or errors reported by the analyzer:

```bash
   flutter analyze
```

   *We enforce a zero-warning policy on all PRs. Code with analyzer warnings
   will not be merged.*

### Conventional Commits

We use the [Conventional Commits](https://www.conventionalcommits.org/)
specification for commit messages. This helps generate clean changelogs.

Format: `<type>(<scope>): <description>`

**Common Types:**

- `feat`: A new feature for the user
- `fix`: A bug fix for the user
- `docs`: Documentation changes
- `style`: Formatting, semi-colons, etc. (no production code change)
- `refactor`: Refactoring production code (no feature or bug change)
- `test`: Adding or formatting tests (no production code change)
- `chore`: Updating build tasks, dependencies, etc.

**Examples:**

- `feat(auth): add role selection screen`
- `fix(map): resolve memory leak on web polyline redraw`
- `docs(readme): add troubleshooting instructions`

### AI-Assisted Contributions

AI tools (ChatGPT, Copilot, Cursor, etc.) are welcome when used responsibly.
However, **do not submit AI-generated code you haven't thoroughly reviewed or
don't understand.** PRs may be closed if code is deemed to be submitted without
proper review or understanding.

---

## 6. Testing

We expect bug fixes and features to be accompanied by tests where applicable.

- Run existing tests locally:

```bash
  flutter test
```

- Write clear unit, widget, or integration tests to verify your implementation.

---

## 7. The Pull Request Process

1. **Verify Your Branch:**
   Ensure the following commands run successfully with zero errors/warnings
   before pushing:

```bash
   dart format --output=none --set-exit-if-changed .
   flutter analyze
   flutter test
```

2. **Push and Open PR:**
   Push your branch to your fork and open a Pull Request against the `main`
   branch of `MediFlow`.
3. **Fill the PR Template:**
   Complete the pull request template checklist.
4. **Include Screenshots:**
   If your PR changes or adds any UI elements, you **must** attach screenshots
   or a screen recording showing the before/after state.
5. **Code Review:**
   At least one maintainer will review your code. Address any feedback and push
   updates directly to your branch.
6. **Merging:**
   Once approved and the CI/CD checks pass, a maintainer will merge your PR.
7. **PR Activity:**
   Please remain responsive. If changes are requested and no updates or
   comments are provided for 10 days, the PR may be closed to manage the review
   queue. It can always be reopened later.

Thank you for helping us make MediFlow better!
