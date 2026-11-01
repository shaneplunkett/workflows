# workflows

Forgejo Actions workflows the other repos call, so each one lives in one
place instead of drifting apart in copies. The forge mirrors this repo to
`shaneplunkett/workflows` on GitHub on every push, and the workflows under
`.github/workflows/` are for callers on GitHub, during the move there.

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

A caller on GitHub uses the mirror's name and the GitHub path:

```yaml
jobs:
  hosts:
    uses: shaneplunkett/workflows/.github/workflows/hosts.yml@v2.0.0
    secrets:
      INPUTS_TOKEN: ${{ secrets.INPUTS_TOKEN }}
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

The called workflow runs as the caller: it checks out the caller's repo,
`$GITHUB_REPOSITORY` is the caller, and it runs on the caller's runner. The
caller keeps the triggers and any `concurrency:` group, because those belong
to the workflow file that starts the run.

To release a change, merge it, then tag `main` with the next version.
Renovate opens the pull requests that move each caller's pin, as long as the
caller's `renovate.json` extends this repo's preset:

```json
{
  "extends": ["local>shane/workflows"]
}
```

`default.json` is that preset. It reads the pins with the `forgejo-tags`
datasource, and turns off the `github-actions` manager's lookup for
`shane/workflows`, which goes to github.com, where `shane` is someone else.
A repo that only wants its pins bumped also sets
`"enabledManagers": ["custom.regex"]`. The preset also lifts the builder's
one-day release age and Sunday schedule for these pins, so a bump opens
as soon as Renovate runs after a tag: the tags are made on purpose, so the
wait guards nothing, and without it a tag made after Sunday morning trailed
by a week.

## checkout

`actions/checkout` as this forge needs it: pinned to v4.4.0, the newest
release that works here, and with `persist-credentials: false`, so the job's
token isn't left in the checkout's git config. Use it in place of
`actions/checkout`:

```yaml
steps:
  - uses: https://git.shaneplunkett.com/shane/workflows/checkout@v1.3.0
```

It takes `ref` and `fetch-depth`, like `actions/checkout`. A step's `uses:`
needs the full URL, because a short `owner/repo` is looked up on Forgejo's
own mirror at `data.forgejo.org`.

The preset keeps Renovate's `actions/checkout` updates in `.forgejo/` below
v5. From v5 on,
checkout stores the job's credentials in a separate file that git on the
host runner never reads, so fetching from the forge fails with
`could not read Username`. The workflows here pin the same release directly.

## tailnet

On GitHub: joins the tailnet as an ephemeral `tag:ci` node through
`tailscale/github-action`, pinned here so every caller runs the same commit.
Tailscale trusts GitHub's OIDC through a federated identity whose subject is
the caller's repo, so the job needs `id-token: write` and holds no Tailscale
secret. The client ID and audience aren't secret either, so callers keep them
in repository variables:

```yaml
permissions:
  contents: read
  id-token: write
steps:
  - uses: shaneplunkett/workflows/tailnet@v1.9.0
    with:
      client-id: ${{ vars.TAILSCALE_CLIENT_ID }}
      audience: ${{ vars.TAILSCALE_AUDIENCE }}
```

The node is gone from the tailnet once the job ends. The tag is fixed: what a
job may do is decided by its GitHub Environment, not by a second tag. A pull
request from a fork gets no OIDC token, so it can't join.

## build.yml

The build check, and on a pull request the derivation diff: the hosts whose
system derivation differs between the pull request's merge base and its
head, which is the list of what merging it would rebuild. The `hosts` job
evaluates the caller's `hydraJobs` at both commits and posts the list as one
comment from `forge-bot`, which it edits on each push. The comment ends with
the commit it's for, and Forgejo keeps its edit history. Then one job per
host builds the hosts in the diff, each its own check on the pull request.
`fail-fast` is off, so one broken host doesn't hide the others. An unchanged
host is the very derivation `main` already built, so a pull request that
changes no host builds nothing: the comment says so, and the one build job
is a placeholder, `build (no changed hosts)`, whose steps all skip. Forgejo
leaves a job with an empty matrix blocked for good, so the placeholder is
what lets the run finish.

An evaluation of caboodle's `hydraJobs` peaks around 14 GB and takes about
two minutes. Two pull requests each running two at once filled the builder's
memory and wedged it, so the builder now runs one full evaluation at a time,
and its peak is one evaluation's 14 GB. The `hosts` job holds a `flock` on
`/var/lib/forgejo-runner/builder/eval.lock` while it evaluates, and another
job waits its turn. Forgejo ignores `concurrency` on a job, and the
workflow-level key would also hold back every host build behind it. `flock`
comes from `util-linux` in the builder's `hostPackages`.

A push to `main` evaluates every host's derivation and writes the mapping
to `/var/lib/forgejo-runner/builder/evals/<repo>/<commit>.json`. It writes a
temp file of its own and renames it into place while it still holds the
lock, so a reader never sees half of one, even when a re-run of the same
commit is evaluating too. That makes a push to `main` take about two
minutes longer to start its builds. A re-run of a commit that already has
the file reuses it, and the log says `Using the cached evaluation`. A pull
request usually branches from a commit `main` has built, so it evaluates
its head, reads the base from that file, and the log says the same. When
the file is missing, because the base predates the cache, was swept or
never ran the push build, the log says `No cached evaluation`; a file that
isn't a non-empty JSON object, say a truncated one, is ignored, and the
log says `Ignoring the cached evaluation`. Either way the job evaluates
the base after the head, inside the same lock, and writes the file for
the next pull request on that base. The caller owns that directory's
retention; caboodle sweeps it with a tmpfiles age rule.

Then a push to `main` builds every host, and roots each build at
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
    uses: shane/workflows/.forgejo/workflows/build.yml@v1.2.0
```

The comment comes from the `forge-bot` token the builder's runner holds as
a credential, the same one `flake-update.yml` uses. Inside a called workflow
only `github.ref` tells a pull request apart, so the pull request's number
comes from it, and its base branch from the API.

## check.yml

The lint check: runs the caller's `scripts/check.sh` inside its flake's
default dev shell, as one check on the pull request. That script is the
caller's one gate, the same one its agents' Stop hook and pre-commit run, so
the shell has to carry every tool it calls. Call it from the same workflow
as `build.yml`, so one pin bump moves both:

```yaml
jobs:
  build:
    uses: shane/workflows/.forgejo/workflows/build.yml@v1.4.0
  check:
    uses: shane/workflows/.forgejo/workflows/check.yml@v1.4.0
```

## flake-update.yml

The `nix flake update` pull request, opened as `forge-bot`. A repo calls it
from a workflow on `schedule` and `workflow_dispatch`, with
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
- **`only`**, default empty. The flake inputs to update, space-separated.
  Empty updates every input.
- **`automerge`**, default `false`. Once every host builds, sets the pull
  request to merge in the repo's default style when its required checks pass.
  `flake-update` itself isn't a required check, so this is the last thing the
  run does.

A second caller for a few inputs, say one that another repo dispatches when it
pushes, gives itself its own `branch` and `concurrency` group, so it never
pushes over the weekly pull request.

## hosts.yml

On GitHub: the derivation diff, the hosts whose `hydraJobs.<host>`
derivation differs between a baseline and the head, and with `build` on, a
build of each changed host pushed to the caller's Attic. It's `build.yml`
rebuilt for hosted runners. A whole colmena hive can outgrow a runner's
16 GB, so `list` reads the host names with `builtins.attrNames`, which
touches no host's config, and each host gets its own `evaluate` job.

`list` resolves the baseline first: a pull request's merge base, or with
`build` on, the commit before a push to main. It reads main's `hosts-<sha>`
mapping for that commit. With none, because it's older than 90 days or from
before the caller used this, `evaluate-base` evaluates the baseline in its
own matrix before the head's starts, so a run never holds both at once. A
push with no commit before it has no baseline, and every host counts as
changed.

Each `evaluate` job evaluates its host once. The installer's pin pins Nix
too, to 2.35.4, which writes the derivation into the store as it evaluates,
and the job checks it's there. It compares the path with the baseline's,
writes the path, peak memory, elapsed time and whether it builds to its
summary, and uploads `head-<host>`, a one-day artifact, before building
anything, so a build that fails still leaves its evaluation in the diff.
Then, with `build` on, a changed host the runner can build, which is
`x86_64-linux`, frees disk, joins the tailnet with `tailnet`, adds the
cache as a substituter with the pull token in Nix's netrc, along with
`extra-substituters`, and builds that same derivation's outputs without
evaluating the flake again. A dry run first logs how many derivations will
build, how many paths will be fetched, and how many Nix "doesn't know how
to build": paths no cache has whose derivation it can't place, which it
then builds anyway. Those get a warning, since they usually mean a missing
cache. A run that only substitutes says 0 and 0. It pushes the closure with
`attic push`, which fails the job if any upload does, and uploads
`built-<host>`. An unchanged host, a Mac, and every host on a fork's pull
request stop after evaluating.

The `hosts` job runs after them all, so on a pull request the comment
arrives after the slowest build. It gathers the evaluations and builds and
writes the diff: the hosts that change, any removed, and with `build` on,
which built and pushed, which failed and which weren't built here. It goes
on the pull request as one comment from the caller's GitHub App, starting
with `<!-- derivation-diff -->` like `build.yml`'s, and each push edits it.
A push to main uploads the mapping as `hosts-<sha>`, kept 90 days, the most
a public repo allows, as long as every host evaluated.

`hosts` is the one to require. It runs whatever happened before it, because
a required job that's skipped counts as passing, and fails when a host
didn't evaluate, at either end, or didn't build or push, or when the
baseline's matrix failed. A failed build still gets the full diff. When an
evaluation is missing, the comment leads with "Incomplete diff", names the
hosts it can't speak for, and only lists changes among the rest.

A rerun keeps the artifacts of the attempt before it, and an upload step
that never runs leaves the old artifact in place, so a rerun that fails
could otherwise show the last attempt's build. Each head job uploads
`start-<host>` with its attempt number before anything else, and stamps its
plan and build records with it too. `hosts` only counts a host's records
from the attempt its marker names. Re-running only the failed jobs keeps
the others' records, since their markers still name the first attempt.

A rerun builds the changed hosts again, and with the closure already in the
cache, that's all fetching: the dry run's count of builds is zero. Checking
the cache instead would need every path in the closure, since one cached
top-level path doesn't say its dependencies are there too.

```yaml
permissions:
  contents: read
  actions: read
  id-token: write

jobs:
  hosts:
    uses: shaneplunkett/workflows/.github/workflows/hosts.yml@v2.1.0
    with:
      build: true
      tailnet-client-id: ${{ vars.TAILSCALE_CLIENT_ID }}
      tailnet-audience: ${{ vars.TAILSCALE_AUDIENCE }}
      cache-endpoint: http://cache.example.ts.net:8080
      cache-name: shane
      cache-public-key: shane:...
      extra-substituters: https://nix-community.cachix.org
      extra-trusted-public-keys: nix-community.cachix.org-1:...
    secrets:
      INPUTS_TOKEN: ${{ secrets.INPUTS_TOKEN }}
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
      ATTIC_PULL_TOKEN: ${{ secrets.ATTIC_PULL_TOKEN }}
      ATTIC_PUSH_TOKEN: ${{ secrets.ATTIC_PUSH_TOKEN }}
```

`INPUTS_TOKEN` is a read-only GitHub token that goes into Nix's
`access-tokens` for the caller's private flake inputs, and `APP_CLIENT_ID`
and `APP_PRIVATE_KEY` are the App's, which only the comment uses. Building
also takes the two Attic tokens: the pull token in the netrc, and the push
token only in the push step's own config. `attic-client` names the client
to push with, read through `--inputs-from .`, so it's the one the caller's
`flake.lock` pins, by default `nixpkgs#attic-client`.

`extra-substituters` and `extra-trusted-public-keys`, space-separated, are
the other caches the caller's hosts pull from. Give the runner every
upstream the Attic cache filters against: Attic leaves out whatever one of
them signed, so a runner without that upstream builds it from source. An
unfree package is the usual case, since cache.nixos.org never has one.

The caller has to grant `actions: read`, for the run that holds the
baseline's mapping, and `id-token: write` to build, for the tailnet. The
`evaluate` jobs take the caller's permissions instead of naming their own,
because a called job that asks for more than the caller granted fails the
whole run, so a caller that only wants the diff leaves `build` off and
grants no `id-token`. Run it on `push` to main and on `pull_request`, with
the build jobs' runner time in mind: `evaluate` gets six hours with `build`
on, the most a hosted job can have. A pull request's own run can upload an
artifact by any name, so only a mapping from a run on main is read. A
called workflow on GitHub sees the caller's event and payload, unlike on
Forgejo, so the pull request's head and base come straight from
`github.event`.

## Tests

`tests/hosts.sh` runs `hosts.yml`'s "Work out the diff" step, pulled out of
the workflow with `yq`, against artifacts it makes up, and checks the
outputs and the summary: a build, no change, failures at the head and the
baseline, the rerun cases above, and a push with no baseline.
`.forgejo/workflows/test.yml` runs it on every pull request here. To run it
yourself:

```sh
nix shell nixpkgs#jq nixpkgs#yq-go -c tests/hosts.sh
```

## Gotchas

- **The `shane` org has to stay public.** Forgejo only expands a workflow
  from another repo when the owner is public, and it reports anything else as
  `failed to access user shane: user does not exist`. It's harmless here,
  because the forge requires signing in to see anything at all.
- **The API can't make an org public.** `PATCH /orgs/{org}` with
  `"visibility": "public"` returns 200 and changes nothing, because public is
  the zero value and Forgejo skips it. Use the org's Settings page.
- **A called workflow only ever sees `workflow_call`.** `github.event_name`
  inside it is never the caller's `push` or `pull_request`. `github.ref` is
  the caller's, though: `refs/heads/main` on a push, `refs/pull/<n>/head` on
  a pull request.
- **Only literals reach a called workflow's inputs.** Forgejo expands it on
  the server without the `github` context, so `with: { x: ${{ github.* }} }`
  arrives empty and the input falls back to its default.
- **A shallow checkout hides its history from a git worktree.** Nix then goes
  looking for the parent commit and fails, so flake refs into a worktree of
  the checkout say `?shallow=1`.
- **`nix build -o` makes a GC root.** The before and after builds in
  `flake-update.yml` link every host's closure from a temp dir, which pins
  them until the dir is gone, so its last step deletes the dir even when an
  earlier one failed. The runner's `TMPDIR` is in its state directory, swept
  a day later, not the private `/tmp` that a restart empties.
