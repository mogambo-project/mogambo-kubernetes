#!/usr/bin/env bash
#
# Bootstrap the SOPS Jenkins jobs into a running Jenkins container.
# This recreates the jobs from the version-controlled definitions in jenkins/jobs/,
# so any developer/machine ends up with the same jobs.
#
# Usage (run from the repo root, i.e. mogambo-kubernetes/):
#   ./jenkins/install-jobs.sh
# Override the container name if yours differs:
#   JENKINS_CONTAINER=my-jenkins ./jenkins/install-jobs.sh
#
# Prerequisites:
#   - The Jenkins container is running (docker compose up -d in bootcamp/setup/).
#   - You have docker access to it.
set -euo pipefail

JEN="${JENKINS_CONTAINER:-setup-jenkins-1}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Installing jobs into container: $JEN"
for job in sops-encrypt sops-decrypt; do
  src="$REPO_ROOT/jenkins/jobs/$job.job.xml"
  [ -f "$src" ] || { echo "ERROR: $src not found"; exit 1; }
  docker exec "$JEN" mkdir -p "/var/jenkins_home/jobs/$job"
  docker cp "$src" "$JEN:/var/jenkins_home/jobs/$job/config.xml"
  docker exec -u root "$JEN" chown -R jenkins:jenkins "/var/jenkins_home/jobs/$job"
  echo "  installed: $job"
done

echo "Reloading Jenkins so it picks up the jobs..."
docker restart "$JEN" >/dev/null
echo "Done. Open http://localhost:8080 — the jobs appear after Jenkins finishes starting."
echo
echo "Reminder: the jobs need two credentials to be fully functional:"
echo "  - github-token  (Secret text)  -> for the encrypt job's Open PR stage"
echo "  - sops-age-key  (Secret file)  -> for the decrypt job"
echo "See jenkins/README.md for how to add them."
