# A self-hosted GitHub Actions runner that carries its own Docker.
FROM docker:29.10.0-dind
RUN apk add --no-cache bash curl jq openssl
COPY job /opt/runner/job
COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh /opt/runner/job/job.sh
ENTRYPOINT ["/usr/local/bin/start.sh"]
CMD []
