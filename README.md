# Beamcove runner

A self-hosted GitHub Actions runner in one Docker image. Each job starts in a fresh container with its
own private Docker, and both are removed when it ends. Only tool, dependency and image caches stay.

## Run it

You need Docker and a GitHub App installed on your organization, with the organization permission
**Self-hosted runners: Read and write**.

```bash
docker build -t beamcove-runner https://github.com/beamcove/beamcove-runner.git
docker run -d --name beamcove-runner --restart unless-stopped --privileged \
  -v beamcove-runner:/var/lib/docker \
  -e RUNNER_ORG=<organization> \
  -e RUNNER_APP_ID=<app id> \
  -e RUNNER_KEY="$(cat <path to the app's .pem file>)" \
  beamcove-runner
```

## Settings

| Setting         | Required | What it is                                                     |
| --------------- | -------- | -------------------------------------------------------------- |
| `RUNNER_ORG`    | Yes      | The GitHub organization                                        |
| `RUNNER_APP_ID` | Yes      | The GitHub App's ID                                            |
| `RUNNER_KEY`    | Yes      | The GitHub App's private key                                   |
| `RUNNER_LABELS` | No       | Comma-separated labels. Default: `self-hosted,linux,<arch>,container` |
| `RUNNER_NAME`   | No       | The name shown on GitHub. Default: the container's hostname    |

`/var/lib/docker` holds the caches. Deleting it only makes the next job slower.

The container runs other containers, so it needs `--privileged` or a container runtime that allows
nested containers. Use it only for repositories you trust: never for a public repository's pull
requests.
