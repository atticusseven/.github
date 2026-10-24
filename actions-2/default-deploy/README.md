# Default Deploy (v2)

**Existing callers that omit both inputs retain their existing deployment behaviour.**

This composite action builds Composer dependencies, deploys files with rsync, then
runs remote WordPress maintenance commands. The two optional inputs below only
affect post-deployment activation and rewrite flushing. They do not change which
plugins Composer installs or rsync deploys, and do not remove unwanted plugin files
from production.

## Optional activation and rewrite inputs

| Input | Default | Behaviour |
| --- | --- | --- |
| `activate-plugins` | `""` | Empty/omitted preserves the existing environment-specific activation command. A non-empty list activates only the named plugins, in caller-supplied order. |
| `flush-rewrites-with-plugins` | `"false"` | False/omitted preserves the existing rewrite command. `"true"` flushes with plugins **and the active theme** loaded. |

Use whitespace-separated WordPress plugin slugs, not Composer package names,
comma-separated lists or plugin file paths. Spaces, tabs, LF and CRLF are supported.
Slugs must start with an ASCII lowercase letter or digit, followed by lowercase
letters, digits, hyphens or underscores. A whitespace-only list is invalid.
The whole list is validated before checkout, Composer or rsync runs; invalid
input fails with a GitHub error annotation.

Explicit activation replaces both environment-specific activation paths, even
for custom environment names. It does not apply the default exclusions: a plugin
explicitly named by the caller is requested even if it is normally excluded.
It does **not** deactivate any other plugins. Already-active plugins stay active;
unrelated inactive plugins are not requested for activation. A missing requested
plugin causes WP-CLI to report an error and fail the deployment step. Activation
is not transactional: plugins activated before a WP-CLI failure are not rolled
back. The action retains `--skip-plugins --skip-themes` during activation.

The rewrite input accepts **only the exact lowercase strings `true` and `false`**.
An explicitly empty value, uppercase variants, `yes`, `1`, surrounding whitespace
and arbitrary non-empty values are rejected before deployment.

With `"true"`, neither `--skip-plugins` nor `--skip-themes` is passed to the
rewrite command. A normal WordPress bootstrap lets plugins and themes register
their custom post types and taxonomies before the rules are rebuilt. This is
useful for routes such as Events, Projects, Resources and project-type taxonomies.
Keeping the theme loaded also preserves theme-registered routes. This executes
normal plugin/theme bootstrap code; ensure that code is safe under WP-CLI.
Its errors propagate normally. The default command continues to skip both.
WordPress must-use plugins can still load even with WP-CLI's `--skip-plugins`.

### Existing activation mode

Existing workflows need no edits. For example (other required inputs still apply):

```yaml
- uses: atticusseven/.github/actions-2/default-deploy@main
  with:
    env: production
    ssh-user: ${{ vars.SSH_USER }}
    ssh-host: ${{ vars.SSH_HOST }}
    ssh-key: ${{ secrets.SSH_PRIVATE_KEY }}
    destination-path: ${{ vars.DESTINATION_PATH }}
    wp-theme: my-theme
    auth-json: ${{ secrets.COMPOSER_AUTH_JSON }}
```

### Explicit activation and plugin-aware rewrite mode

The following is illustrative, **not** Lia Ghilardi's final production plugin list.
Use the ref containing this change when testing; the example branch must be
reviewed and released before a production workflow adopts it.

```yaml
- uses: atticusseven/.github/actions-2/default-deploy@feature/configurable-plugin-activation-and-rewrite-flush
  with:
    env: production
    ssh-user: ${{ vars.SSH_USER }}
    ssh-host: ${{ vars.SSH_HOST }}
    ssh-key: ${{ secrets.SSH_PRIVATE_KEY }}
    destination-path: ${{ vars.DESTINATION_PATH }}
    wp-theme: my-theme
    auth-json: ${{ secrets.COMPOSER_AUTH_JSON }}
    activate-plugins: >-
      advanced-custom-fields-pro
      admin-columns-pro
      classic-editor
      a7-events
      a7-projects
      a7-resources
    flush-rewrites-with-plugins: "true"
```

The inputs are independent: explicit activation can retain legacy flushing, and
plugin-aware flushing can retain the default activation mode.

## Original deployment contract

Audited against commit `f618389` before editing. Existing inputs/defaults remain:
`env=production`, `ssh-port=22`, `dot-env=""`; `ssh-user`, `ssh-host`, `ssh-key`,
`destination-path`, `wp-theme`, and `auth-json` have no defaults and are required.
`env` is also marked required in the action definition.

The original order is checkout, PHP setup (8.3 with Composer v2), authentication
and `.env` writes, Composer diagnostics, root Composer install, theme Composer
install, file cleanup, SSH setup, rsync, WP-CLI install, environment-specific
activation, database upgrade, conditional SG cache purge, rewrite flush.
The new validation step runs first without changing that existing order.

### Composer and file deployment

Diagnostics run:

```bash
composer --version
composer diagnose || true
```

Both dependency installations use `ramsey/composer-install@v3` with exactly:

```yaml
composer-options: "--no-dev --optimize-autoloader --no-interaction --no-progress"
```

The first runs at the repository root; the second uses
`working-directory: "wp-content/themes/${{ inputs.wp-theme }}"`.
These are action invocations, not an inline `composer install` command; the
third-party action controls the exact underlying invocation and caching.
Root `auth.json` and `.env` are written from the existing inputs using `printf`.
Their handling is unchanged.

Rsync remains:

```bash
rsync -avPC --delete --no-perms \
  --include-from='.rsyncinclude' \
  --exclude-from='.rsyncignore' \
  . "server:${{ inputs.destination-path }}"
```

### Original WordPress commands (unchanged default paths)

Production (`env == 'production'`):

```bash
wp plugin activate --exclude=password-protected,disable-emails --all \
  --skip-plugins --skip-themes \
  --ssh="server:${{ inputs.destination-path }}"
```

Dev/staging (`env == 'dev' || env == 'staging'`):

```bash
wp plugin activate --exclude=updraftplus --all \
  --skip-plugins --skip-themes \
  --ssh="server:${{ inputs.destination-path }}"
```

Other environment names have no default activation step. Exclusion means
**do not activate**, not **deactivate**; excluded plugins already active in the
database stay active.

Database update:

```bash
wp core update-db --skip-plugins --skip-themes \
  --ssh="server:${{ inputs.destination-path }}"
```

SG cache handling:

```bash
if wp plugin is-active sg-cachepress \
  --skip-plugins --skip-themes \
  --ssh="server:${{ inputs.destination-path }}"; then
  if wp sg status dynamic-cache \
    --skip-plugins --skip-themes \
    --ssh="server:${{ inputs.destination-path }}"; then
    wp sg purge \
      --skip-themes \
      --ssh="server:${{ inputs.destination-path }}"
  fi
fi
```

Rewrite flush:

```bash
wp rewrite flush \
  --skip-plugins --skip-themes \
  --ssh="server:${{ inputs.destination-path }}"
```

The original inline destination interpolation and SSH alias remain unchanged.
Default activation/rewrite commands contain no added environment variables or
error suppression. Bash steps use GitHub's `bash --noprofile --norc -eo pipefail`
behaviour: activation, database, purge and rewrite failures stop subsequent steps.
Nonzero SG checks inside `if` skip cache operations without failing the step;
Composer diagnose remains explicitly non-fatal.

New inputs enter the shell only via step environment variables, not interpolation
into shell source. Validation emits a normalized, validated list as a step output.
Explicit activation reads it into a quoted Bash argument array, preserving order.
No `eval`, unquoted expansion or shell execution of input is used.

## Local regression tests

No testing framework/dependencies are added. Ruby 2.6+ provides YAML, Minitest,
JSON and process execution in its standard library:

```bash
ruby actions-2/default-deploy/test/deploy_test.rb
```

The [baseline fixture](test/baseline.yml) records the original inputs and all 15
steps from `f618389`. Tests check every existing input, step definition, command
body and order (allowing only the new gating conditions).
They execute the relevant extracted Bash blocks with a recording WP-CLI stub,
using GitHub's Bash flags. No Composer, rsync, SSH setup or website connection is
executed. Default command sequences and injected failures are compared directly
with the baseline in production/dev/staging/custom environments and cache paths.
Tests cover single/multiple/multiline plugins, argument order, invalid names,
injection attempts, booleans, error propagation and safe opt-in path arguments.

For real WordPress activation state and rewrite rules, use Docker:

```bash
bash actions-2/default-deploy/test/integration.sh
```

This downloads public MariaDB/WordPress CLI images and WordPress 6.8.3, creates
uniquely named disposable containers/network/volume, publishes no host ports and
mounts no host files. It uses only isolated test credentials and cleans up on exit.
It runs the same suite with the integration test enabled. Only the `wp --ssh`
transport is replaced with `docker exec`; action Bash blocks still run unchanged.
It verifies already-active/requested inactive/unrelated inactive plugins, actual
activation-hook order, missing-plugin failure, plugin CPT/taxonomy rules and
theme CPT rules. Fixtures model route registrations; they are not Lia's actual
plugins or theme. Without Docker integration, that one test is reported skipped.

No live deployment, real SSH transport, premium plugins, GitHub runner, or
production application bootstrapping is validated by these local tests.

## Read-only investigation: environment-specific plugin files

**Deployment configuration determines which plugins exist in an environment;
plugin activation determines which of those plugins run.**

Current v2 behaviour:

- Root and theme installs always use `--no-dev`, including dev/staging. Merely
  moving a staging utility into `require-dev` would therefore omit it everywhere
  under this action, not just production.
- There is no environment-specific dependency profile, manifest selection or
  dependency filtering in this action. `env` only gates the legacy activation
  steps. `.env` contents are supplied by the caller and deployed unchanged.
- Callers supply `.rsyncinclude` and `.rsyncignore`. Rsync filtering determines
  file transfer/deletion along with `--delete`; excluded destination files are
  generally protected from deletion without `--delete-excluded`. Changing an
  include/exclude list alone is not proof that old production plugins disappeared.
- The hard-coded exclusions are activation policy, not file policy. They cannot
  remove plugins or deactivate a plugin that was already active.
- The older, separate [v1 Composer action](../../actions/install-composer-dependencies/action.yml)
  invokes [dependency removal](../../actions/delete-dev-only-plugins/index.js)
  for production by deleting selected `wpackagist-plugin/*` requirements from
  a manifest. This does not exist in v2 and is not changed here. Mutating a
  manifest independently of its lockfile is not a recommended future pattern.

Recommended future work (not implemented here):

1. Projects should own reproducible environment dependency sets and lockfiles.
   Where appropriate, stage-only utilities can be `require-dev`, but a future
   explicitly opted-in staging profile would need to install dev dependencies.
   Distinct Composer manifests/lockfiles or a separate locked staging utility
   package set can avoid deploying unrelated development tooling to staging.
   Keep premium authentication outside those manifests.
2. Project-owned per-environment deployment include lists can complement those
   dependency profiles, without cloning the shared action. Explicitly test rsync
   rule ordering and deletion semantics; never add `--delete-excluded` globally
   as a shortcut, since it could delete unrelated server-managed files.
3. Inventory existing files and database activation state first. Back up and test
   on staging; deactivate retiring utilities deliberately, then remove only
   identified files in a separately reviewed migration. Check MU plugins,
   drop-ins and runtime configuration as well as ordinary plugins.
4. Introduce future profiles as opt-in/versioned behaviour, preserve legacy
   defaults for older sites, and transition callers individually with dry runs
   and rollback plans. These two inputs alone do not implement file segregation.

### Hassell Inclusion: evidence and follow-up

No Hassell Inclusion workflow or project configuration is present in this
repository; its production activation problem cannot be attributed conclusively.
No consuming repository was accessed or modified.

Evidence worth checking against that site's actual setup:

- The v2 production exclusion prevents requesting `disable-emails`, but will
  not deactivate it if already active (including database imports).
- Dev/staging activation excludes only `updraftplus`, so it can request
  `disable-emails`. Inspect the actual resolved `env`, destination and action ref.
- The separate [DB-to-dev action](../db-to-dev/action.yml) explicitly activates
  `disable-emails` and `password-protected` on its configured dev target. Verify
  that workflow's destination inputs if it is used; this is not evidence that it
  ran against Hassell production.
- Inspect the consuming workflow, pinned action implementation, deployment logs,
  Composer manifests/locks, rsync filters, `.env`/WP configuration, database active
  plugin state (and multisite network state if relevant), MU plugins, and any
  activation hooks, imports or scheduled commands that could change that state.

An unrelated example-workflow issue is left unchanged: the v2 dev example omits
`env` (thus defaults to production), and both v2 examples show the same dev-looking
destination. These examples are not Hassell configuration and do not establish
the cause of its incident.
