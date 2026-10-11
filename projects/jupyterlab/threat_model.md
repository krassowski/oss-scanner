# Threat model

## What this project does and where untrusted input enters

JupyterLab is an extensible environment for interactive and reproducible computing, based on the Jupyter Notebook and Architecture. This repository holds the frontend (`packages/`, which runs as one page in the browser) and a Jupyter Server extension (`jupyterlab/`). [jupyterlab_server](https://github.com/jupyterlab/jupyterlab_server) serves the page and the settings, workspaces, themes and translations APIs. It is installed from PyPI like the other dependencies, and defects in it are in scope: JupyterLab publishes the advisories for it.

A script that runs in the JupyterLab page can use the Jupyter Server REST API as the user: it can read and write files, run code in a kernel and open a terminal. So JavaScript execution in the JupyterLab origin is code execution on the server. This is the main class of defect we want found.

Untrusted input comes from:

- files that someone else wrote and the user opens: notebooks with their saved outputs, Markdown, HTML, images including SVG, PDF, CSV, JSON, Vega and Mermaid;
- cells that the user pastes from the clipboard or drops;
- settings files that the user imports, or that another user writes on a shared file system;
- language pack catalogues (the `Plural-Forms` header becomes code);
- PyPI metadata in the extension manager, and the news feed;
- changes from other users of a shared document (`@jupyter/ydoc`) when real-time collaboration is installed;
- links from other web pages to the JupyterLab URL;
- requests to `/lab/api/` from authenticated users, in deployments that restrict them (kernels and terminals disabled, an extension allowlist, locked plugins), such as a JupyterHub for a course.

JupyterLab follows the [Jupyter security model](https://jupyter-server.readthedocs.io/en/stable/operators/security.html#our-security-model): output that the user generated is trusted, and other output is not.

- Markdown and raw cells are always sanitized.
- Untrusted `text/html` outputs are sanitized. Untrusted JavaScript and SVG outputs are not rendered.
- Trusted outputs are not sanitized, and their `<script>` elements run. A notebook is trusted when the server's signature matches, or after the Trust Notebook command. The output of a cell becomes trusted when the user runs the cell.
- The HTML viewer runs no scripts until the user presses Trust HTML. A command link button in untrusted content asks the user before it runs the command.

Running a script or a command from untrusted content without the user's consent is a vulnerability. So is making content trusted that the user did not trust.

## Components that matter most / least

Most (directories under `packages/`):

- the HTML sanitizer and the command linker, in `apputils`;
- rendering: `rendermime`, `markedparser-extension`, `mathjax-extension`, and the document viewers (`markdownviewer`, `htmlviewer`, `imageviewer`, `pdf-extension`, `csvviewer`, `json-extension`, `vega5-extension`, `mermaid`, `javascript-extension`, `toc`);
- notebook trust, copy and paste, and the models that apply changes from the shared document: `notebook`, `cells`, `outputarea`, `docregistry`, `codemirror`;
- settings, themes and translations: `settingeditor`, `settingregistry`, the theme manager in `apputils`, `translation`;
- `services`, which sends the token and the XSRF cookie.

Most, in Python: the handlers in `jupyterlab/handlers/` and the extension managers in `jupyterlab/extensions/`, including the allowlist and the blocklist.

Least: build and release tooling (`buildutils/`, `dev_mode/`, `scripts/`, `jupyter lab build`, `jupyter labextension`), `examples/`, `docs/`, and the test helpers in `galata/` and `packages/testing`.

## How to exercise it

The repository is at `/src`, built in dev mode. JupyterLab is installed from `/src` in editable mode, in a virtual environment on PATH.

- Browser tests: start a server with `cd /src/galata && jupyter lab --config ./jupyter_server_test_config.py --allow-root &`, then run `jlpm playwright test --project jupyterlab test/jupyterlab/notebook-trust.test.ts`. This server has no token and no XSRF check. For a finding about authentication, use `jupyter lab --dev-mode --allow-root --no-browser`. A new galata test is the best way to show that opening or clicking something runs a script.
- Unit tests: `cd /src/packages/<name> && jlpm build:test && jlpm jest -i test/<file>.spec.ts`. The sanitizer cases are in `packages/apputils/test/sanitizer.spec.ts`.
- Python tests: `cd /src && python -m pytest jupyterlab/tests`.

## How you rate severity

The levels follow JupyterLab's published advisories, given by ID.

- Critical: script or code execution from an attacker with no account, when the user does nothing except start JupyterLab. An unauthenticated request that makes a handler run code or read files is also critical.
- High: script execution from untrusted content after one ordinary action by the user: opening a file (GHSA-4952-p58q-6crx, GHSA-9q39-rmj3-p4r2), one click (GHSA-mqcg-5x36-vfcg), a paste (GHSA-6966-vjj6-99xv), opening an image in a new tab (GHSA-gx64-gj6p-pc4c), or importing a settings file (GHSA-pppj-hq3g-57pj). The token sent to another origin after one click is high (GHSA-44cc-43rp-5947). So is code execution by an authenticated user where the operator disabled kernels and terminals (GHSA-37w4-hwhx-4rc4).
- Medium: script execution that needs a non-default setting, a race, input from a privileged party such as a translation catalogue, or a malicious package in the user's extension manager search (GHSA-3jqq-pw4j-pqcj, GHSA-jwrc-gm9j-263p, GHSA-vmhf-c436-hxj4). A bypass of an operator restriction without code execution is medium (GHSA-89vp-jrxv-24w8, GHSA-h5v5-8746-g7mm, GHSA-3325-v43h-43rv).
- Low: hardening that stock JupyterLab does not reach (GHSA-vvfj-2jqx-52jm, GHSA-whvh-wf3x-g77j).

A user who can start a kernel or a terminal can already run any code on the server. A server-side defect that only such a user can reach counts only where kernels and terminals are disabled or run on another host, and the report must state that condition. Every report states its preconditions: the versions, the settings, and each action the user takes.

## Reports and patches

Give the JupyterLab version first, then the commit, the input and the steps. Include a test that fails before the fix: galata, jest or pytest.

## Anything to leave alone

- Scripts in content that the user trusted. This is the design.
- Code that the user runs: kernels, the console and terminals.
- Installed extensions and packages, which are trusted code. Language pack catalogues are the exception.
- The test server configurations: `galata/jupyter_server_test_config.py` and `docker/jupyter_server_config.json`.
- Defects in jupyter_server, nbformat, Tornado and other dependencies that no JupyterLab code reaches.
- HTTP headers such as Content-Security-Policy, which jupyter_server sets.
- A slow tab caused by a large file, unless it affects other users of the server.
- The real-time collaboration server and transport, in [jupyter-collaboration](https://github.com/jupyterlab/jupyter-collaboration). The shared document models in this repository stay in scope.
