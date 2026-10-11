# workflows

Forgejo Actions workflows the other repos call, so each one lives in one
place instead of drifting apart in copies.

## Calling one

Pin a tag, not `main`, so a change here reaches a repo only when that repo
moves its pin:

```yaml
jobs:
  update:
    uses: shane/workflows/.forgejo/workflows/flake-update.yml@v1.0.0
    with:
      notes: scripts/flake-update-notes.sh
```

The called workflow runs as the caller: it checks out the caller's repo,
`$GITHUB_REPOSITORY` is the caller, and it runs on the caller's runner. The
caller keeps the triggers and any `concurrency:` group, because those belong
to the workflow file that starts the run.

To release a change, merge it, then tag `main` with the next version and move
each caller's pin in its own pull request.

## build.yml

The build check: one job per host in the caller's `hydraJobs`, each its
own check on the pull request. `fail-fast` is off, so one broken host doesn't
hide the others. On a push it also roots each build at
`/var/lib/forgejo-runner/builder/roots/<repo>/<host>`, so the builder's
weekly GC keeps it in the cache. A repo calls it from a workflow on
`pull_request`, plus `push` to `main` if it wants that.

```yaml
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    uses: shane/workflows/.forgejo/workflows/build.yml@v1.1.0
```

## flake-update.yml

The weekly `nix flake update` pull request, opened as `forge-bot`. A repo
calls it from a workflow on `schedule` and `workflow_dispatch`, with
`concurrency: { group: flake-update, cancel-in-progress: true }` so a second
run replaces the first.

The caller's flake lists the hosts to build as `hydraJobs.<host>`, each the
host's system derivation. For a colmena hive that's
`hydraJobs = self.colmenaHive.toplevel;`.

Inputs, all optional:

- **`title`**, default `flake.lock: update every input`. The pull request's
  title.
- **`reviewer`**, default `metrokitten`. Asked to review once the description
  is done. Empty asks no one.
- **`branch`**, default `update/flake-lock`. Where the update is pushed.
- **`notes`**, default empty. A script in the caller's repo that prints
  changelogs as markdown, given the old and new `flake.lock`. Empty leaves the
  Changelogs section out.

## Gotchas

- **The `shane` org has to stay public.** Forgejo only expands a workflow
  from another repo when the owner is public, and it reports anything else as
  `failed to access user shane: user does not exist`. It's harmless here,
  because the forge requires signing in to see anything at all.
- **The API can't make an org public.** `PATCH /orgs/{org}` with
  `"visibility": "public"` returns 200 and changes nothing, because public is
  the zero value and Forgejo skips it. Use the org's Settings page.
- **A shallow checkout hides its history from a git worktree.** Nix then goes
  looking for the parent commit and fails, so flake refs into a worktree of
  the checkout say `?shallow=1`.
