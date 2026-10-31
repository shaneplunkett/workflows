# workflows

Shared Forgejo Actions pieces that other repos on the forge call: reusable
workflows in `.forgejo/workflows/`, step actions such as `checkout/`, and the
Renovate preset in `default.json`. The forge mirrors the repo to
`shaneplunkett/workflows` on GitHub on every push, tags included, and
`.github/workflows/` holds the reusable workflows GitHub callers use. The
README is the reference for each one, its inputs, and the gotchas behind its
choices; read the section for the piece you're changing first.

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
   preset lifts the release age wait and the Sunday schedule for these pins.
   Watch them: the release is done when every bump is green, and Shane merges
   them.

## Testing before a release

Nothing here runs until a caller uses it. Push the change on a branch, then
push a throwaway branch in a caller repo (caboodle) with a
`workflow_dispatch` workflow that uses this repo at your branch. Dispatch it,
read the run's log, then delete both throwaway branches. Give
`flake-update.yml` a test `branch`, `reviewer: ""` and a test `title`, so it
opens its own pull request and leaves the real update alone, and leave
`automerge` off, since its pull requests always target `main`. Try a merge
call on its own pull request into a throwaway base instead, with a `pending`
commit status standing in for the checks.

## Pins that stay put

In `.forgejo/`, `actions/checkout` stays on v4.4.0, through `checkout/` and
the preset's `allowedVersions`, for the reason in the README. A newer
release goes in only after a throwaway run proves it can fetch from the forge
on the host runner. GitHub-hosted runners don't have that problem, so
`.github/` takes new releases.
