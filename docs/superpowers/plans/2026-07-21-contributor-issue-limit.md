# Contributor Issue Assignment Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub Actions workflow that automatically unassigns a non-maintainer contributor from an issue, with an explanatory comment, if assigning them would put them over 4 open assigned issues at once.

**Architecture:** A single new workflow file, `.github/workflows/contributor-issue-limit.yml`, triggered on the `issues: assigned` event. One job runs `actions/github-script@v7` to check the assignee's collaborator permission level, count their other open assigned issues via the search API, and unassign + comment if the count is already at or above the cap. `CONTRIBUTING.md` gets a short note documenting the automated cap next to the existing manual-assignment instructions.

**Tech Stack:** GitHub Actions, `actions/github-script@v7` (bundles `@actions/github` / Octokit), YAML.

## Global Constraints

- Cap is 4 open assigned issues per contributor (spec: "Problem"/"Logic" sections).
- Trigger is `issues: assigned` only, firing once per assignee added (spec: "Trigger").
- Skip if `github.event.assignee.type == 'Bot'` (spec: "Logic" step 1).
- Exempt assignees whose `repos.getCollaboratorPermissionLevel` permission is `admin` or `write` (spec: "Logic" step 2).
- Count via search query `repo:<owner>/<repo> is:issue is:open assignee:<username>`, excluding the current issue from the count to avoid search-index lag (spec: "Logic" step 3, adapted for correctness — see Task 1 Step 3 notes).
- On exceeding the cap: `issues.removeAssignees` for that user, then `issues.createComment` listing their other current open issues (spec: "Logic" step 4).
- No label changes anywhere (spec: "Non-goals").
- Job uses `continue-on-error: true`; workflow permissions are `issues: write`, `contents: read` (spec: "Failure handling", "Implementation notes").
- New workflow file, not a job inside `issue-automation.yml` (spec: "Implementation notes").
- Avoid em dashes and generic AI-sounding phrasing in all comment text and commit messages (user instruction).

---

### Task 1: Create the contributor issue limit workflow

**Files:**
- Create: `.github/workflows/contributor-issue-limit.yml`

**Interfaces:**
- Produces: a standalone GitHub Actions workflow, no other task depends on its internals.

- [ ] **Step 1: Write the workflow file**

Create `.github/workflows/contributor-issue-limit.yml` with this exact content:

```yaml
name: Contributor Issue Assignment Limit

on:
  issues:
    types: [assigned]

permissions:
  issues: write
  contents: read

jobs:
  enforce-issue-limit:
    name: Enforce Contributor Issue Cap
    runs-on: ubuntu-latest
    continue-on-error: true # Ensure automation glitches do not block maintainers

    steps:
      - name: Check and enforce open issue cap
        uses: actions/github-script@v7
        with:
          script: |
            const MAX_OPEN_ISSUES = 4;
            const assignee = context.payload.assignee;

            if (!assignee || assignee.type === 'Bot') {
              console.log('Assignee missing or is a bot, skipping.');
              return;
            }

            const { owner, repo } = context.repo;
            const issue = context.payload.issue;

            let permission = 'none';
            try {
              const response = await github.rest.repos.getCollaboratorPermissionLevel({
                owner,
                repo,
                username: assignee.login,
              });
              permission = response.data.permission;
            } catch (error) {
              console.log(`Could not read permission for ${assignee.login}, treating as none.`);
            }

            if (permission === 'admin' || permission === 'write') {
              console.log(`${assignee.login} is a maintainer (${permission}), no cap applied.`);
              return;
            }

            const searchResult = await github.rest.search.issuesAndPullRequests({
              q: `repo:${owner}/${repo} is:issue is:open assignee:${assignee.login}`,
              per_page: 100,
            });

            const otherOpenIssues = searchResult.data.items.filter(
              (item) => item.number !== issue.number
            );

            if (otherOpenIssues.length < MAX_OPEN_ISSUES) {
              console.log(`${assignee.login} has ${otherOpenIssues.length} other open issues, within the cap.`);
              return;
            }

            await github.rest.issues.removeAssignees({
              owner,
              repo,
              issue_number: issue.number,
              assignees: [assignee.login],
            });

            const issueList = otherOpenIssues
              .map((item) => `- #${item.number} ${item.title}`)
              .join('\n');

            await github.rest.issues.createComment({
              owner,
              repo,
              issue_number: issue.number,
              body: [
                `Hi @${assignee.login}, thanks for picking this up.`,
                '',
                `You are already assigned to ${MAX_OPEN_ISSUES} open issues, which is our per-contributor limit, so you have been unassigned from this one to keep it available for other contributors.`,
                '',
                'Your current open issues:',
                issueList,
                '',
                'Once you close or hand back one of these, comment here again and a maintainer can reassign this issue to you.',
              ].join('\n'),
            });
```

**Note on the count logic:** The spec's step 3 counts open assigned issues including the one just assigned. This plan instead counts the assignee's *other* open issues (excluding the current one by number) and unassigns when that count is already at or above 4. This sidesteps a real risk: GitHub's search index can lag a few seconds behind a webhook firing, so the just-assigned issue might not appear in search results yet. Excluding it by number makes the check correct regardless of indexing delay, while producing the identical outcome (block the 5th concurrent assignment).

- [ ] **Step 2: Validate YAML syntax**

Run:

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/contributor-issue-limit.yml')); print('valid yaml')"
```

Expected output: `valid yaml`

- [ ] **Step 3: Validate the embedded JS has no syntax errors**

The `script:` block is JavaScript executed by `actions/github-script`. Extract and check it with Node directly:

```bash
python3 -c "
import yaml
doc = yaml.safe_load(open('.github/workflows/contributor-issue-limit.yml'))
script = doc['jobs']['enforce-issue-limit']['steps'][0]['with']['script']
open('/tmp/_gh_script_check.js', 'w').write('async function main(){\n' + script + '\n}')
"
node --check /tmp/_gh_script_check.js && echo "script syntax ok"
```

Expected output: `script syntax ok`

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/contributor-issue-limit.yml
git commit -m "feat(ci): cap contributors at 4 open assigned issues

Maintainers stay exempt via collaborator permission checks. Adds a
workflow that unassigns and comments when a non-maintainer contributor
would be assigned a 5th open issue at once."
```

---

### Task 2: Document the cap in CONTRIBUTING.md

**Files:**
- Modify: `CONTRIBUTING.md:107-109` (end of "Claiming and Creating Issues" section)

**Interfaces:**
- Consumes: none.
- Produces: none, documentation only.

- [ ] **Step 1: Add a bullet documenting the automated cap**

In `CONTRIBUTING.md`, the "Claiming and Creating Issues" section currently ends with:

```markdown
4. **Inactive Issues:** If an assigned issue has no meaningful updates for 7
   days, it may be unassigned to allow others to work on it. If you need more
   time, just leave a comment with a progress update.
```

Replace it with (adds a new point 5, keeps point 4 unchanged):

```markdown
4. **Inactive Issues:** If an assigned issue has no meaningful updates for 7
   days, it may be unassigned to allow others to work on it. If you need more
   time, just leave a comment with a progress update.
5. **Issue Limit:** Contributors can be assigned to a maximum of 4 open
   issues at a time. If you are already at the limit, an assignment bot will
   automatically unassign you from any new issue and leave a comment
   explaining why. Finish or hand back one of your current issues to free up
   a slot.
```

- [ ] **Step 2: Verify the change**

```bash
grep -n "Issue Limit" CONTRIBUTING.md
```

Expected: prints the new line 5 heading, confirming the edit landed.

- [ ] **Step 3: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: note the 4-issue contributor cap in CONTRIBUTING.md"
```

---

## Self-Review Notes

- **Spec coverage:** Trigger (Task 1 Step 1 `on:`), exemption check (Task 1 Step 1 permission block), counting (Task 1 Step 1 search block, with the indexing-lag adaptation called out), enforcement (Task 1 Step 1 removeAssignees + createComment), non-goals (no label code anywhere), failure handling (`continue-on-error: true`), file location (new standalone workflow) are all covered by Task 1. CONTRIBUTING.md documentation is covered by Task 2.
- **Placeholder scan:** none found, all steps have literal file content and exact commands.
- **Type consistency:** only one script, no cross-task signatures to reconcile.
