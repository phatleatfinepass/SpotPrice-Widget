# Contributing

Thanks for helping improve SpotPriceWidget.

## Branch workflow

- Start work from `maintenance` and open changes against `maintenance`.
- Keep `stable` release-ready. It is updated only after the macOS and iOS builds pass and the release package is verified.
- Avoid force-pushes and history rewrites on either shared branch.

## Codex working context on the maintained Mac

Resolve this file, [README.md](README.md) and the
[engineering playbook](docs/APP-WIDGET-ENGINEERING-PLAYBOOK.md) from the actual
checkout. Pass the installed shared placement guard, then bind this chat with
`codex-project-context` using those entry points, the authorized objective/scope
and integration target `refs/heads/maintenance`, matching
`.codex/project-context.json`. The folder name `main` does not change this branch
workflow.

Check the binding before production. Assess deliberate source/document changes
before refreshing the exact previous binding; a fork or handoff reloads local
context and gets its own binding. Build and evidence output still needs approved
in-checkout destinations and file-lifecycle handling. Before delivery/integration,
require `check --target-check` and use `run --target-check` for its shell producer.
Review source, related docs and required evidence together against the receiving
branch. Bounded routing and target checks do not establish semantic integration or
release readiness; the checks below and the release process still apply.

## Before submitting

Run from the verified checkout root with the full Xcode app. For Codex on the
maintained Mac, use the installed context and lifecycle helpers; an active binding
must already match this task. This recipe allocates its own operation and keeps
script temporaries, npm cache and both Xcode build directories inside it:

```bash
set -euo pipefail
workspace_root="$(git rev-parse --show-toplevel)"
context_session="${CODEX_THREAD_ID:-${CODEX_SESSION_ID:?A current Codex session is required}}"
codex-project-context check --workspace "$workspace_root"
validation_run="$(codex-file-lifecycle create --workspace "$workspace_root" \
  --task "$context_session" --purpose 'Spot Price scoped checks and platform builds')"
for output_path in \
  "$validation_run/validation.log" \
  "$validation_run/scratch" \
  "$validation_run/scratch/tmp" \
  "$validation_run/scratch/npm-cache" \
  "$validation_run/scratch/DerivedData-macOS" \
  "$validation_run/scratch/DerivedData-iOS" \
  "$workspace_root/backend/grid-emissions-relay/node_modules"; do
  codex-project-guard check --workspace "$workspace_root" --destination "$output_path"
done
codex-project-context run --workspace "$workspace_root" -- \
  codex-file-lifecycle run "$validation_run" -- /bin/bash -c '
    set -euo pipefail
    validation_root="$1"
    exec > "$validation_root/validation.log" 2>&1
    mkdir -p "$validation_root/scratch/tmp" "$validation_root/scratch/npm-cache"
    export TMPDIR="$validation_root/scratch/tmp/"
    export npm_config_cache="$validation_root/scratch/npm-cache"
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    script/test-grid-conditions.sh
    script/validate-product.sh
    (cd backend/grid-emissions-relay && npm ci --ignore-scripts && npm run check)
    xcodebuild -quiet -project SpotPriceWidget.xcodeproj \
      -scheme SpotPriceWidget -destination "platform=macOS" \
      -derivedDataPath "$validation_root/scratch/DerivedData-macOS" \
      CODE_SIGNING_ALLOWED=NO build
    xcodebuild -quiet -project SpotPriceWidget.xcodeproj \
      -scheme SpotPriceWidget -destination "generic/platform=iOS Simulator" \
      -derivedDataPath "$validation_root/scratch/DerivedData-iOS" \
      CODE_SIGNING_ALLOWED=NO build
  ' validation "$validation_run"
```

The child writes stdout and stderr to `validation.log` inside its allocated run.
Inspect that log on success or failure before assessment. A nonzero producer exit
leaves the lifecycle operation held for failure-evidence assessment; the log is
preserved even when a test removes its own compiler scratch. Preserve required
evidence and assets, then use `codex-file-lifecycle assess` with the factual
assessment and `finish` for this exact run. Failure output stays while diagnosis
needs it; maintain a hold with owner and resolving trigger if assessment cannot
close. Do not remove
the run before required evidence has been preserved. Refresh the context only
after reviewing any changed source or document baseline.

The relay's in-checkout `node_modules/` is a rebuildable dependency installation,
not part of disposable run cleanup. Keep it while used and remove it only under
an exact authorized rebuildable-cache cleanup. Generated `dist/` packages belong
to the project: retain them through assessment and any requested handover, and
keep accepted release assets and their verification evidence. Ignore status or
chat completion never authorizes deleting deliverables. Other existing caches,
installed apps and service data are outside this operation's cleanup scope.

Check small and medium widget previews in light and dark appearances when changing layout, typography, color bands, or charts.

Release packaging is documented in [docs/RELEASE.md](docs/RELEASE.md). The approved public artifact is the ad-hoc signed Universal disk image produced in `direct` mode; do not describe it as Developer ID-signed or Apple-notarized.

## Credentials and private data

Never commit API keys, passwords, tokens, personal data, `.env`/`.dev.vars` files, local Xcode configurations, or screenshots containing credentials. Production Fingrid credentials are encrypted Cloudflare Worker secrets. A contributor’s direct-provider credential belongs in macOS Keychain and may enter only a local Debug bundle through the source installer’s process-local injection path. That Debug bundle contains the key in plaintext and must never be distributed or retained after testing.
