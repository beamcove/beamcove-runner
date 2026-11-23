# What one job runs in: GitHub's runner, with the build basics a hosted runner has.
FROM ghcr.io/actions/actions-runner:2.338.2
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates curl git jq \
       libssl-dev pkg-config python3 unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*
COPY --from=docker/compose-bin:v5.8.0 /docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
COPY --from=docker/buildx-bin:0.39.1 /buildx /usr/local/lib/docker/cli-plugins/docker-buildx
COPY job.sh /home/runner/job.sh
USER runner
ENTRYPOINT ["/home/runner/job.sh"]
