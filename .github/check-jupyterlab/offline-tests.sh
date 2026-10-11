#!/bin/bash
# Runs inside the finished scanner image, with no network, from .github/workflows/check-jupyterlab.yaml.
# Writes one log per check and a results table to /out. Exits 1 if any required check fails.
set -o pipefail
cd /src || exit 1
status=0
echo "| Check | Result |" > /out/results.md
echo "| --- | --- |" >> /out/results.md

# Runs one check, shows its output in a collapsed group of the job log, and records the result.
# With `optional`, a failure is recorded but does not fail the job.
run_check() {
  local name=$1 kind=$2
  shift 2
  echo "::group::$name"
  if "$@" 2>&1 | tee "/out/$name.log"; then
    result=pass
  elif [[ $kind == optional ]]; then
    result="fail (not required)"
  else
    result=FAIL
    status=1
  fi
  echo "::endgroup::"
  echo "| $name | $result |" >> /out/results.md
}

# This script is not an interactive shell, so ~/.bashrc is not read: the tools must be on PATH from the image.
tools_on_path() {
  command -v node python jupyter jlpm && node --version && python --version && jupyter --version && jlpm --version
}

sanitizer_unit_tests() {
  cd packages/apputils && jlpm jest -i test/sanitizer.spec.ts
}

server_starts() {
  (cd galata && jupyter lab --config ./jupyter_server_test_config.py --allow-root > /out/server.log 2>&1 &)
  for _ in $(seq 180); do
    curl -sf http://localhost:8888/lab -o /dev/null && return 0
    sleep 1
  done
  cat /out/server.log
  return 1
}

# Notebook trust, and the sanitizer applied to pager HTML, in headless Chromium.
browser_trust_tests() {
  cd galata && jlpm playwright test --project jupyterlab test/jupyterlab/notebook-trust.test.ts --reporter=list --workers=1
}

# The Python tests, to find the ones that need a network. CI runs `jupyter lab build` first, which this image skips.
python_tests() {
  timeout 1500 python -m pytest -q -n 2 --dist loadgroup --timeout 300 -p no:cacheprovider jupyterlab/tests
}

run_check tools-on-path required tools_on_path
run_check sanitizer-unit-tests required sanitizer_unit_tests
run_check server-starts required server_starts
run_check browser-trust-tests required browser_trust_tests
run_check python-tests optional python_tests

if [[ -d galata/test-results ]]; then
  cp -r galata/test-results /out/galata-test-results
fi
exit $status
