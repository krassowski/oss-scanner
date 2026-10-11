#!/bin/bash
# Runs inside the finished scanner image, with no network, from .github/workflows/check-jupyterlab.yaml.
# Writes one log per check and a results table to /out. Exits 1 if any required check fails.
cd /src || exit 1
status=0
echo "| Check | Result |" > /out/results.md
echo "| --- | --- |" >> /out/results.md

# Runs one check, prints its log in a collapsed group of the job log, and records the result.
# With `optional`, a failure is recorded but does not fail the job.
# Each check runs in a subshell, so that its `cd` does not change the directory of the checks after it. The output goes
# to a file, not through a pipe: a process that a check leaves running (a server, a test worker) would keep a pipe open
# and the check would never end.
run_check() {
  local name=$1 kind=$2
  shift 2
  local start=$SECONDS
  if ("$@") > "/out/$name.log" 2>&1 < /dev/null; then
    result=pass
  elif [[ $kind == optional ]]; then
    result="fail (not required)"
  else
    result=FAIL
    status=1
  fi
  echo "::group::$name: $result"
  cat "/out/$name.log"
  echo "::endgroup::"
  echo "| $name | $result ($((SECONDS - start)) s) |" >> /out/results.md
}

# This script is not an interactive shell, so ~/.bashrc is not read: the tools must be on PATH from the image.
tools_on_path() {
  command -v node python jupyter jlpm && node --version && python --version && jupyter --version && jlpm --version
}

sanitizer_unit_tests() {
  cd packages/apputils && timeout -k 10 600 jlpm jest -i test/sanitizer.spec.ts
}

# The server runs in the background for the browser test. Its subshell has its output redirected as a whole, so that
# no process is left holding the output of this check.
server_starts() {
  (cd galata && exec jupyter lab --config ./jupyter_server_test_config.py --allow-root) > /out/server.log 2>&1 < /dev/null &
  for _ in $(seq 120); do
    if curl -sf --max-time 10 http://localhost:8888/lab -o /out/lab.html; then
      grep -q 'jupyter-config-data' /out/lab.html && return 0
    fi
    sleep 1
  done
  cat /out/server.log
  return 1
}

# Notebook trust, and the sanitizer applied to pager HTML, in headless Chromium.
browser_trust_tests() {
  cd galata && timeout -k 10 1200 jlpm playwright test test/jupyterlab/notebook-trust.test.ts --project=jupyterlab \
    --reporter=list --workers=1
}

# The Python tests. The deselected ones run `jupyter lab build` or install npm packages, which needs the network.
python_tests() {
  local t=jupyterlab/tests
  timeout -k 30 900 python -m pytest -q -n 2 --dist loadgroup --timeout 300 -p no:cacheprovider "$t" \
    --deselect "$t/test_build_api.py::TestBuildAPI::test_build" \
    --deselect "$t/test_build_api.py::TestBuildAPI::test_clear" \
    --deselect "$t/test_jupyterlab.py::TestExtension::test_build" \
    --deselect "$t/test_jupyterlab.py::TestExtension::test_build_check" \
    --deselect "$t/test_jupyterlab.py::TestExtension::test_build_custom" \
    --deselect "$t/test_jupyterlab.py::TestExtension::test_build_custom_minimal_core_config" \
    --deselect "$t/test_jupyterlab.py::TestExtension::test_build_splice_packages" \
    --deselect "$t/test_jupyterlab.py::TestExtension::test_install_and_uninstall_pinned" \
    --deselect "$t/test_jupyterlab.py::TestExtension::test_install_and_uninstall_pinned_folder" \
    --deselect "$t/test_jupyterlab.py::TestExtension::test_uninstall_core_extension"
}

run_check tools-on-path required tools_on_path
run_check sanitizer-unit-tests required sanitizer_unit_tests
run_check server-starts required server_starts
run_check browser-trust-tests required browser_trust_tests
run_check python-tests required python_tests

if [[ -d galata/test-results ]]; then
  cp -r galata/test-results /out/galata-test-results
fi
exit $status
