---
name: pr
description: Push the branch and open a PR (GitHub) or MR (GitLab) with a conventional description.
disable-model-invocation: true
---
1. Run the `verify` skill. If it fails, stop and show me.
2. Platform: if there's a `.gitlab-ci.yml` or a GitLab remote, use `glab`; otherwise `gh`. Base: the default branch.
3. Body:
   - a summary, from the commits
   - the ticket link, taken from the branch name (e.g. `feature/PROJ-123-…`)
   - what changed
   - the exact verification output
   - anything left undone
4. `git push -u origin HEAD`, then `gh pr create --base <base> --title … --body …` or `glab mr create …`. Both ask me first.
5. Print the URL.
