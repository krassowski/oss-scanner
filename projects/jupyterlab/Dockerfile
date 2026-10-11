# JupyterLab built from source the way its CI builds it (scripts/ci_install.sh in the jupyterlab repository), with a
# headless Chromium so that the app and rendered notebooks can be opened in a browser during the scan.
FROM node:22-bookworm
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git python3 python3-dev python3-venv \
    && rm -rf /var/lib/apt/lists/*

# A virtual environment on PATH, so that python, pip, jupyter and jlpm work in every shell, interactive or not.
RUN python3 -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH

# CI removes the global yarn, so that the build uses only the yarn that jlpm bundles.
RUN rm -f /usr/local/bin/yarn /usr/local/bin/yarnpkg

# scanner contract: the checkout lives inside the image, at /src
COPY . /src
WORKDIR /src

# The Python package and its test dependencies. SKIP_JUPYTER_BUILDER skips the build hook, which would hide the
# JavaScript build output inside pip's metadata step; the next step runs that build with its output in the log.
RUN mkdir -p ~/.jupyter \
    && pip install --upgrade pip \
    && SKIP_JUPYTER_BUILDER=1 pip install -e ".[dev,test]"

# The JavaScript packages and the dev mode application in dev_mode/static. This is most of the build time.
RUN jlpm install && jlpm build && test -s dev_mode/static/index.html

# Galata (the Playwright test helpers) and the browser it uses, fetched now because the scan has no network.
RUN cd galata && jlpm build && jlpm playwright install --with-deps --only-shell chromium

# Run the sanitizer's unit tests so you know the image works, but do not let a failing test abort the build.
RUN cd packages/apputils && jlpm build:test \
    && (jlpm jest -i test/sanitizer.spec.ts || echo "WARNING: apputils sanitizer tests reported failures")
