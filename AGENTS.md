# workflows

Shared Forgejo Actions pieces that other repos on the forge call: reusable
workflows in `.forgejo/workflows/`, step actions such as `checkout/`, and the
Renovate preset in `default.json`. The README is the reference for each one,
its inputs, and the gotchas behind its choices; read the section for the piece
you're changing first.

## Releasing

Callers pin a tag, so a change reaches a repo only when that repo's pin moves.

1. Land the change through a pull request, filed with the `file-pr` skill.
   Shane merges.
2. Tag `main` with the next version (patch for a fix, minor for something new,
   major when a caller has to change) and push the tag. Tags are permanent:
   a follow-up fix is a new tag.
3. Start Renovate (`ssh root@builder systemctl start renovate`) or wait for
   Sunday's run. It opens a pin bump in every caller that extends the preset.
   The release is done when those bumps are green.

## Testing before a release

Nothing here runs until a caller uses it. Push the change on a branch, then
push a throwaway branch in a caller repo (nix-config is the quickest) with a
`workflow_dispatch` workflow that uses this repo at your branch. Dispatch it,
read the run's log, then delete both throwaway branches. Give
`flake-update.yml` a test `branch`, `reviewer: ""` and a test `title`, so it
opens its own pull request and leaves the real update alone.

## Pins that stay put

`actions/checkout` stays on v4.4.0, through `checkout/` and the preset's
`allowedVersions`, for the reason in the README. A newer release goes in only
after a throwaway run proves it can fetch from the forge on the host runner.
