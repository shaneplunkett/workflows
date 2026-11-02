# workflows

Reusable GitHub Actions workflows that the other repos call, in
`.github/workflows/`, and the Renovate preset in `default.json`. The README
is the reference for each one, its inputs, and the reasons behind its
choices; read the section for the piece you're changing first. CI is checks
only: nothing here builds or pushes a closure, since builds happen on
Shane's desktop.

## Releasing

Callers pin a tag, so a change reaches a repo only when that repo's pin moves.
The agent that makes the change owns the release, with Shane's merge as its
cue, and stays until the last bump is green.

1. Land the change through a pull request, filed with the `pr` skill. Its
   body names the bump (patch for a fix, minor for something new, major when
   a caller has to change) and which callers feel it: a repo only feels
   changes to the pieces it calls. Shane merges.
2. Tag `main` with that version, an annotated tag, and push the tag. Tags
   are permanent: a follow-up fix is a new tag.
3. Bump the pin in each caller with a pull request of its own: caboodle and
   ai-skills today (`gh search code --owner shaneplunkett
   shaneplunkett/workflows` finds them). Renovate would move caboodle's on
   Sunday, inside its weekly batch, and moves no one else's. The release is
   done when every bump is green, and Shane merges them.

## Testing before a release

Nothing runs here without a caller. Push the change on a branch here, then
a throwaway branch in a caller (caboodle) whose workflow uses this repo at
your branch. Open a throwaway pull request (`gh pr create -R
shaneplunkett/caboodle`) so `pull_request` runs, or dispatch it (`gh
workflow run <file> -R shaneplunkett/caboodle --ref <branch>`), and read the
run with `gh run view --log`. GitHub finds a dispatched workflow by its file
name on the default branch and then runs the file at your ref, so a caller
that's new on your branch borrows the name of one `main` has for the test.
Give `flake-update.yml` a test `branch`, `reviewer: ""` and a test `title`,
so it opens its own pull request and leaves the real update alone. Close the
pull request and delete both branches when you're done.
