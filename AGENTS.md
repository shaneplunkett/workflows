# workflows

Shared Actions pieces that the other repos call, in two trees: reusable
workflows in `.forgejo/workflows/` for callers on the forge, and the same
pieces in `.github/workflows/` for callers on GitHub, during the move
there, plus step actions such as `checkout/` and `tailnet/`, and the
Renovate preset in `default.json`. The forge mirrors the repo to
`shaneplunkett/workflows` on GitHub on every push, tags included, with
`--mirror`, so a branch that only exists on GitHub is gone at the next
push. The README is the reference for each one, its inputs, and the gotchas
behind its choices; read the section for the piece you're changing first.
The GitHub workflows use `actions/checkout`, the caller's GitHub App for
anything that writes, GitHub's API and artifacts; none of the forge's
runner-side state or `forge-bot`.

## Releasing

Callers pin a tag, so a change reaches a repo only when that repo's pin moves.
The agent that makes the change owns the release, with Shane's merge as its
cue, and stays until the last bump is green.

1. Land the change through a pull request, filed with the `pr` skill. Its
   body names the bump (patch for a fix, minor for something new, major when
   a caller has to change) and which callers feel it: a repo only feels
   changes to the pieces it calls. Shane merges.
2. Tag `main` with that version and push the tag. Tags are permanent: a
   follow-up fix is a new tag.
3. Start Renovate (`ssh root@builder systemctl start renovate`). It opens a
   pin bump in every caller that extends the preset, straight away: the
   preset lifts the release age wait and the Sunday schedule for these pins,
   on both names, so one run moves a caller's `.forgejo/` and `.github/`
   pins. Watch them: the release is done when every bump is green, and Shane
   merges them. (`gh workflow run renovate.yml -R shaneplunkett/caboodle`
   runs GitHub's Renovate, whose pull requests are a preview until cutover.)

## Testing before a release

`tests/` holds what can run without a caller, and the pull request's
`test` check runs it; extend `tests/hosts.sh` when you change the diff
step's logic. Everything else runs only once a caller uses it. Push the change on a branch, then
push a throwaway branch in a caller repo (caboodle) with a
`workflow_dispatch` workflow that uses this repo at your branch. Dispatch it,
read the run's log, then delete both throwaway branches. Give
`flake-update.yml` a test `branch`, `reviewer: ""` and a test `title`, so it
opens its own pull request and leaves the real update alone, and leave
`automerge` off, since its pull requests always target `main`. Try a merge
call on its own pull request into a throwaway base instead, with a `pending`
commit status standing in for the checks.

For a GitHub workflow, push both branches to the forge, which mirrors them,
never straight to GitHub. Then open the throwaway pull request on the
mirror (`gh pr create -R shaneplunkett/caboodle`), so `pull_request` runs,
or dispatch (`gh workflow run <file> -R shaneplunkett/caboodle --ref
<branch>`), and read the run with `gh run view --log`. GitHub finds a
dispatched workflow by its file name on the default branch and then runs
the file at your ref, so a caller that's new on your branch borrows the
name of one `main` has, say `tailnet.yml`, for the test. Close the pull
request and delete the forge branches when you're done.

## Pins that stay put

In `.forgejo/`, `actions/checkout` stays on v4.4.0, through `checkout/` and
the preset's `allowedVersions`, for the reason in the README. A newer
release goes in only after a throwaway run proves it can fetch from the forge
on the host runner. GitHub-hosted runners don't have that problem, so
`.github/` takes new releases.
