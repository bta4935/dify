# base image
FROM python:3.12-slim-bookworm AS base

WORKDIR /app/api

# Install Poetry
ENV POETRY_VERSION=2.0.1
RUN pip install --no-cache-dir poetry==${POETRY_VERSION}

# Configure Poetry
ENV POETRY_CACHE_DIR=/tmp/poetry_cache
ENV POETRY_NO_INTERACTION=1
ENV POETRY_VIRTUALENVS_IN_PROJECT=true
ENV POETRY_VIRTUALENVS_CREATE=true
ENV POETRY_REQUESTS_TIMEOUT=15

FROM base AS packages

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc g++ libc-dev libffi-dev libgmp-dev libmpfr-dev libmpc-dev

# Install Python dependencies
COPY api/pyproject.toml api/poetry.lock ./
RUN poetry install --sync --no-cache --no-root

# production stage
FROM base AS production

ENV FLASK_APP=app.py
ENV EDITION=SELF_HOSTED
ENV DEPLOY_ENV=PRODUCTION
ENV CONSOLE_API_URL=[http://127.0.0.1](http://127.0.0.1):5001
ENV CONSOLE_WEB_URL=[http://127.0.0.1](http://127.0.0.1):3000
ENV SERVICE_API_URL=[http://127.0.0.1](http://127.0.0.1):5001
ENV APP_WEB_URL=[http://127.0.0.1](http://127.0.0.1):3000

# Ensure we listen on the port Render expects
ENV PORT=5001
EXPOSE 5001

# set timezone
ENV TZ=UTC

WORKDIR /app/api

RUN \
    apt-get update \
    # Install dependencies
    && apt-get install -y --no-install-recommends \
        # basic environment
        curl nodejs libgmp-dev libmpfr-dev libmpc-dev \
        # For Security
        expat libldap-2.5-0 perl libsqlite3-0 zlib1g \
        # install a package to improve the accuracy of guessing mime type and file extension
        media-types \
        # install libmagic to support the use of python-magic guess MIMETYPE
        libmagic1 \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Copy Python environment and packages
ENV VIRTUAL_ENV=/app/api/.venv
COPY --from=packages ${VIRTUAL_ENV} ${VIRTUAL_ENV}
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# Download nltk data
RUN python -c "import nltk; nltk.download('punkt'); nltk.download('averaged_perceptron_tagger')"

ENV TIKTOKEN_CACHE_DIR=/app/api/.tiktoken_cache
RUN python -c "import tiktoken; tiktoken.encoding_for_model('gpt2')"

# Copy source code directly
COPY api/ /app/api/

# Create a simple entrypoint script
RUN echo '#!/bin/bash\ncd /app/api\npython -m gunicorn app:app --bind 0.0.0.0:$PORT --timeout 360 --workers 1 --worker-class gevent --worker-connections 10' > /entrypoint.sh
RUN chmod +x /entrypoint.sh

ARG COMMIT_SHA
ENV COMMIT_SHA=${COMMIT_SHA}

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
