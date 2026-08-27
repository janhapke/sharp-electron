#!/usr/bin/env bash
# Prepares a release: runs the full build+test pipeline, bumps
# package/package.json's version, and prints the remaining manual steps.
#
# Deliberately does NOT run `npm publish` itself. Publishing to a public
# registry is exactly the kind of hard-to-reverse, externally-visible action
# that should always get an explicit human confirmation, no matter how
# automated the rest of the pipeline is (see README.md's "Releasing" section;
# the /rebuild-for-version command applies the same principle to version bumps).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: $0 <new-version>   e.g. $0 0.35.3-electron.1" >&2
  exit 1
fi

./scripts/build-all.sh

node -e "
  const fs = require('fs');
  const path = 'package/package.json';
  const p = JSON.parse(fs.readFileSync(path));
  p.version = '$VERSION';
  // The non-Linux fallback re-exports real sharp, aliased to 'sharp-upstream'
  // (deliberately not named 'sharp' — see package/index.d.ts) — keep it
  // pinned to the upstream version this release tracks (the part before
  // '-electron.N').
  p.dependencies['sharp-upstream'] = 'npm:sharp@' + '$VERSION'.split('-')[0];
  fs.writeFileSync(path, JSON.stringify(p, null, 2) + '\n');
"

# Keep README.md's install snippets pointing at the version being released,
# and refresh the packaged copy (package-local.sh ran before the bump above,
# so package/README.md still has the old version at this point).
sed -i -E "s|(@janhapke/sharp-electron@)[0-9][0-9A-Za-z.-]*|\1$VERSION|g" README.md
cp README.md package/README.md

cat <<EOF

Both gates passed and package/ is built fresh. Bumped to $VERSION in
package/package.json (including its 'sharp' fallback dependency) and in
README.md's install snippets.

Remaining manual steps:
  1. Add a CHANGELOG.md entry for $VERSION (move "Unreleased" content under a new heading)
  2. Review the diff, then commit:
       git add -A && git commit -m "Release $VERSION"
  3. Tag it:
       git tag v$VERSION
  4. Publish (this is the step this script deliberately does not do for you).
     --tag latest is required, not optional: every version this project
     publishes has a '-electron.N' suffix, which npm/semver treats as a
     prerelease, so a plain 'npm publish' refuses to touch the 'latest' dist-tag
     on its own (npm error: "You must specify a tag using --tag when publishing
     a prerelease version"). Without --tag latest, 'npm install @janhapke/sharp-electron'
     with no version (or the 'latest' dist-tag) would resolve to nothing.
     --access public is no longer needed on the command line — it's already
     set via package/package.json's publishConfig.
       cd package && npm publish --tag latest
  5. Push:
       git push && git push --tags

EOF
