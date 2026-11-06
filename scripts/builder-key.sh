#!/bin/bash
# The key a build image is kept under in a registry: a digest of what the image is made
# of, the build tools and the upstream tarballs at their locked digests.
set -euo pipefail
cd "$(dirname "$0")/.."
git ls-files -s -- docker/Dockerfile.build 'components/*/*.lock' scripts/fetch-sources.sh | sha256sum | cut -c1-16
