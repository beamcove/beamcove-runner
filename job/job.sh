#!/usr/bin/env bash
# Runs one job with the one-time registration the manager created, then exits.
set -euo pipefail
config=$JIT_CONFIG
unset JIT_CONFIG
cd /home/runner
exec ./run.sh --jitconfig "$config"
