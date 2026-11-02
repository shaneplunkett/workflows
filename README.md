# workflows

Reusable GitHub Actions workflows the other repos call, so each one lives in
one place instead of drifting apart in copies: `check.yml` runs a repo's
gate, and `flake-update.yml` opens its lock bump. `default.json` is the
Renovate preset. CI here is checks only: nothing builds or pushes a closure.

## Calling one

Pin a tag, not `main`, so a change here reaches a repo only when that repo
moves its pin:

```yaml
jobs:
  check:
    uses: shaneplunkett/workflows/.github/workflows/check.yml@v3.0.0
    secrets:
      INPUTS_TOKEN: ${{ secrets.INPUTS_TOKEN }}
```

The called workflow runs as the caller: it checks out the caller's repo,
`$GITHUB_REPOSITORY` is the caller, and `github.event` is the caller's
`push` or `pull_request`. The caller keeps the triggers, the permissions and
any `concurrency:` group, because those belong to the workflow file that
starts the run.

`INPUTS_TOKEN` is a read-only GitHub token that goes into Nix's
`access-tokens`, for the caller's private flake inputs.

## Renovate

Renovate runs on caboodle alone. caboodle's `renovate.json` extends this
repo's preset with `github>shaneplunkett/workflows`, which is `default.json`.
The preset lifts the release age wait for the pins on
`shaneplunkett/workflows`, since the tags are made on purpose. caboodle
groups every update into its Sunday pull request, so a new tag lands there
unless its pin is bumped by hand first. Nothing moves the pins in other
callers, like ai-skills: they're bumped by hand.

## check.yml

Runs the caller's `scripts/check.sh` inside its flake's default dev shell,
as one check. That script is the caller's one gate, the same one its
agents' Stop hook and pre-commit run, so the shell has to carry every tool
it calls. The shell comes from the public caches, so a tool none of them
has, an unfree one like Terraform, compiles on every run. Call it from its
own workflow:

```yaml
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  check:
    uses: shaneplunkett/workflows/.github/workflows/check.yml@v3.0.0
    secrets:
      INPUTS_TOKEN: ${{ secrets.INPUTS_TOKEN }}
```

## flake-update.yml

`nix flake update`, as a pull request opened by the caller's GitHub App,
from `APP_CLIENT_ID` and `APP_PRIVATE_KEY`. The lock commit is the App's
too, authored with its bot user's noreply address. It pushes the bump
before opening the pull request, so the caller's checks run on its real
head, then fills the description in with the moved inputs, the changelogs
and the lock file, and asks for a review, which the App can do and a pull
request's own author can't. It builds nothing. A notes script that fails
leaves a line pointing at the run in the description and fails the job.

Inputs, all optional:

- **`title`**, default `flake.lock: update every input`. The pull request's
  title.
- **`reviewer`**, default `shaneplunkett`. Asked to review once the
  description is done. Empty asks no one.
- **`branch`**, default `update/flake-lock`. Where the update is pushed.
- **`notes`**, default empty. A script in the caller's repo that prints
  changelogs as markdown, given the old and new `flake.lock`. Empty leaves
  the Changelogs section out.
- **`only`**, default empty. The flake inputs to update, space-separated.
  Empty updates every input.

A caller runs it on `schedule` or `workflow_dispatch`, with a
`concurrency` group that cancels in progress, so a second run replaces the
first rather than racing it to push. A second caller for a few inputs gives
itself its own `branch` and `concurrency` group, so it never pushes over
the main update.

```yaml
on:
  schedule:
    - cron: "0 11 * * 5"
  workflow_dispatch:

concurrency:
  group: flake-update
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  update:
    uses: shaneplunkett/workflows/.github/workflows/flake-update.yml@v3.0.0
    with:
      notes: scripts/flake-update-notes.sh
    secrets:
      INPUTS_TOKEN: ${{ secrets.INPUTS_TOKEN }}
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```
