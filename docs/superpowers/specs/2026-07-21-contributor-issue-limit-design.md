# Contributor Issue Assignment Limit

## Problem

Contributors can currently be assigned an unlimited number of open issues at once. This lets a single person hold onto many issues while making progress on none of them, blocking other contributors from picking up that work. MediFlow's `CONTRIBUTING.md` already asks contributors to comment and wait for a maintainer to assign an issue, but nothing enforces a cap once a maintainer does the assigning.

## Goal

Automatically stop a non-maintainer contributor from being assigned more than 4 open issues at a time, and tell them (and the issue) why.

## Trigger

New workflow: `.github/workflows/contributor-issue-limit.yml`

```yaml
on:
  issues:
    types: [assigned]
```

GitHub fires this event once per assignee added to an issue. `github.event.assignee.login` is the exact user who was just assigned, so the job never needs to diff assignee lists.

## Logic

1. **Skip bots.** If `github.event.assignee.type == 'Bot'`, exit.
2. **Exempt maintainers/collaborators.** Call `repos.getCollaboratorPermissionLevel` for the assignee. If the permission is `admin` or `write`, exit without any check. Only contributors with `read` or `none` permission are subject to the cap.
3. **Count open assigned issues.** Query the search API:
   `repo:<owner>/<repo> is:issue is:open assignee:<username>`
   This counts only open issues (closed ones never count toward the cap) and excludes pull requests via `is:issue`, even though PRs share the same assignee field.
4. **Enforce the cap.** If the count is greater than 4:
   - Remove the user from the issue's assignees (`issues.removeAssignees`), reverting the issue to unassigned.
   - Post a comment on the issue that tags the user, states they've hit the 4-issue cap, lists their current open assigned issues (number + title, linked) so they know what to wrap up, and invites them to comment again once they have room.
5. **If the count is 4 or fewer**, do nothing further; the assignment stands.

## Non-goals

- No label changes. The repo has no "in progress" or "claimed" label to reconcile, so none is added or removed.
- No changes to how contributors claim issues (commenting to request assignment, per `CONTRIBUTING.md` section 3) or to the existing 7-day inactive-issue unassignment policy. Those are unaffected.
- Does not apply to pull requests, only issues.

## Failure handling

The job sets `continue-on-error: true`, matching the pattern already used in `issue-automation.yml`, so a transient GitHub API error doesn't block other automation or show as a failing check on unrelated activity.

## Implementation notes

- Implemented as a single job using `actions/github-script@v7` for the permission lookup, search query, unassign call, and comment post.
- Permissions block: `issues: write`, `contents: read` (same as the existing `issue-automation.yml` workflow).
- Keep this as its own workflow file rather than a new job in `issue-automation.yml`, since it has a distinct trigger (`issues: assigned`, not `opened`) and a distinct concern.
