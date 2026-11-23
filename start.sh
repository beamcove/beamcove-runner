#!/usr/bin/env bash
# Starts this container's own Docker, then runs GitHub Actions jobs one at a time. Each job gets a
# fresh container and a private Docker, and both are removed when it ends. Only the caches stay.
set -uo pipefail

: "${RUNNER_ORG:?set RUNNER_ORG to the GitHub organization}"
: "${RUNNER_APP_ID:?set RUNNER_APP_ID to the GitHub App ID}"
: "${RUNNER_KEY:?set RUNNER_KEY to the GitHub App private key}"

case $(uname -m) in
  aarch64 | arm64) architecture=ARM64 ;;
  *) architecture=X64 ;;
esac
labels=${RUNNER_LABELS:-self-hosted,linux,$architecture,container}
name=${RUNNER_NAME:-$(hostname)}

job_image="runner-job"
docker_image=docker:29.10.0-dind
cache="runner-cache"
images="runner-images"
current=
docker_pid=

# The key stays in this container's memory-backed folder and never reaches a job.
key=/run/runner/key
mkdir -p /run/runner
(umask 077 && printf '%b\n' "$RUNNER_KEY" >"$key")
unset RUNNER_KEY
openssl pkey -in "$key" -noout 2>/dev/null || {
  echo "RUNNER_KEY isn't a private key" >&2
  exit 1
}

base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

app_jwt() {
  local now header payload signature
  now=$(date +%s)
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | base64url)
  payload=$(printf '{"iat":%s,"exp":%s,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$RUNNER_APP_ID" | base64url)
  signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$key" | base64url)
  printf '%s.%s.%s' "$header" "$payload" "$signature"
}

github() {
  local token=$1 method=$2 path=$3
  shift 3
  curl -fsS -X "$method" -H "Authorization: Bearer $token" -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' "https://api.github.com$path" "$@"
}

# A registration that works for one job.
registration() {
  local runner=$1 jwt installation token body
  jwt=$(app_jwt) || return 1
  installation=$(github "$jwt" GET "/orgs/$RUNNER_ORG/installation" | jq -er .id) || return 1
  token=$(github "$jwt" POST "/app/installations/$installation/access_tokens" | jq -er .token) || return 1
  body=$(jq -cn --arg name "$runner" --arg labels "$labels" \
    '{name: $name, runner_group_id: 1, work_folder: "_work", labels: ($labels | split(","))}')
  github "$token" POST "/orgs/$RUNNER_ORG/actions/runners/generate-jitconfig" -d "$body" |
    jq -er .encoded_jit_config
}

remove_job() {
  local id=$1
  [ -n "$id" ] || return 0
  docker rm -f "$id" >/dev/null 2>&1
  # What the job started in its private Docker goes too. Its image layers stay as a cache.
  docker exec "$id-docker" sh -c \
    'docker ps -aq | xargs -r docker rm -f; docker volume prune -af; docker network prune -f' >/dev/null 2>&1
  docker rm -f "$id-docker" >/dev/null 2>&1
  docker volume rm "$id-work" >/dev/null 2>&1
}

stop() {
  remove_job "$current"
  [ -z "$docker_pid" ] || kill "$docker_pid" 2>/dev/null
  wait "$docker_pid" 2>/dev/null
  exit 0
}
trap stop TERM INT

run_job() {
  local id=$1 config ready=
  config=$(registration "$name-$id") || {
    echo "couldn't get a registration from GitHub"
    return 1
  }

  docker volume create "$id-work" >/dev/null
  docker volume create "$cache" >/dev/null
  docker run --rm --user root -v "$id-work:/home/runner/_work" -v "$cache:/cache" \
    --entrypoint chown "$job_image" runner:docker /home/runner/_work /cache || return 1

  docker run -d --name "$id-docker" --privileged -e DOCKER_TLS_CERTDIR= \
    -v "$id-work:/home/runner/_work" -v "$images:/var/lib/docker" \
    "$docker_image" dockerd --host=tcp://127.0.0.1:2375 --host=unix:///var/run/docker.sock >/dev/null || return 1
  for _ in $(seq 1 60); do
    if docker exec "$id-docker" docker info >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  [ -n "$ready" ] || {
    echo "the job's Docker didn't start"
    return 1
  }

  # Sharing the network puts a service the job publishes on its localhost, as on a hosted runner.
  JIT_CONFIG=$config docker run --rm --name "$id" --network "container:$id-docker" -e JIT_CONFIG \
    -e DOCKER_HOST=tcp://127.0.0.1:2375 -e AGENT_TOOLSDIRECTORY=/cache/tools -e CARGO_HOME=/cache/cargo \
    -e RUSTUP_HOME=/cache/rustup -e npm_config_cache=/cache/npm -e GRADLE_USER_HOME=/cache/gradle \
    -v "$id-work:/home/runner/_work" -v "$cache:/cache" "$job_image"
}

# This container's own Docker. A restart can leave a stale pid file on its disk.
find /var/run -maxdepth 2 -name 'docker*.pid' -delete 2>/dev/null
dind dockerd --host=unix:///var/run/docker.sock >/var/log/dockerd.log 2>&1 &
docker_pid=$!
for _ in $(seq 1 60); do
  docker info >/dev/null 2>&1 && break
  sleep 1
done
docker info >/dev/null 2>&1 || {
  echo "Docker didn't start. This container needs to be able to run containers." >&2
  tail -5 /var/log/dockerd.log >&2
  exit 1
}

echo "Preparing the job image"
docker build -q -t "$job_image" /opt/runner/job >/dev/null || exit 1
docker ps -aq | xargs -r docker rm -f >/dev/null 2>&1
docker volume ls -q --filter name='^job-' | xargs -r docker volume rm >/dev/null 2>&1

echo "$name is ready for jobs"
while true; do
  id=job-$(openssl rand -hex 4)
  current=$id
  run_job "$id" &
  wait $! || sleep 30
  remove_job "$id"
  current=
done
