#!/bin/bash
set -eu
set -o pipefail

# This script uses the scripts/build-static-site.sh provided in the container
# and customizes the entrypoint based on what the user has provided.
# We derive variables from the environment instead of command line

COMMAND="/bin/bash /code/scripts/build_static_site.sh"

# Target is required
if [ -z "${SC_TARGET}" ]; then
   SC_TARGET="${GITHUB_WORKSPACE}/docs"        
fi
COMMAND="${COMMAND} --target ${SC_TARGET}"

if [ ! -z "${SC_PROJECT}" ]; then
    COMMAND="${COMMAND} --project ${GITHUB_WORKSPACE}/${SC_PROJECT}"
fi

if [ ! -z "${SC_PROJECT_FILE}" ]; then
    COMMAND="${COMMAND} --project-file ${GITHUB_WORKSPACE}/${SC_PROJECT_FILE}"
fi

if [ ! -z "${SC_WEIGHTS}" ]; then
    COMMAND="${COMMAND} --weights ${GITHUB_WORKSPACE}/${SC_WEIGHTS}"
fi

if [ ! -z "${SC_NOBACKEND}" ]; then
    COMMAND="${COMMAND} --no-backend"
fi

if [ ! -z "${SC_BACKEND_DIR}" ]; then
    COMMAND="SOURCECRED_BIN=${SC_BACKEND_DIR} ${COMMAND}"
fi

# Clean up any previous runs (deployed in docs folder)
# This command needs to be run relative to the sourcecred repository
# which is the WORKDIR under /code in the base container
rm -rf "${SC_TARGET}"
echo "${COMMAND}"
${COMMAND}

# This interacts with node sourcecred.js
# Load it twice so we can access the scores -- it's a hack, pending real instance system
/bin/bash /code/docker-entrypoint.sh load --project "${GITHUB_WORKSPACE}/${SC_PROJECT}" --weights "${GITHUB_WORKSPACE}/${SC_WEIGHTS}"
/bin/bash /code/docker-entrypoint.sh scores "${SC_PROJECT_ID}" | jq '.' > "${GITHUB_WORKSPACE}/${SC_SCORES_JSON}"

# Now we want to interact with the GitHub repository
# The GitHub workspace has the root of the repository
cd "${GITHUB_WORKSPACE}"
echo "Found files in workspace:"
ls

echo "GitHub Actor: ${GITHUB_ACTOR}"
git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
git branch
git config --global user.name "github-actions"
git config --global user.email "github-actions@users.noreply.github.com"

# Automated means that we push to a branch, otherwise we open a pull request
if [ ! -z "${SC_AUTOMATED}" == "true" ]; then
    echo "Automated PR requested"
    UPDATE_BRANCH="${SC_BRANCH_AGAINST}"
else
    UPDATE_BRANCH="update/sourcecred-cred-$(date '+%Y-%m-%d')"
fi

export UPDATE_BRANCH
echo "Branch to update is ${UPDATE_BRANCH}"
git checkout -b ${UPDATE_BRANCH}
git branch

if [ ! -z "${SC_AUTOMATED}" == "true" ]; then
    git pull origin "${UPDATE_BRANCH}" || echo "Branch not yet on remote"
    git add "${SC_TARGET}/*"
    git add "${SC_SCORES_JSON}"
    git commit -m "Automated deployment to update cred in ${SC_TARGET} $(date '+%Y-%m-%d')"
    git push origin "${UPDATE_BRANCH}"
else
    git add "${SC_TARGET}/*"
    git add "${SC_SCORES_JSON}"
    git commit -m "Automated deployment to update ${SC_TARGET} static files $(date '+%Y-%m-%d')"
    git push origin "${UPDATE_BRANCH}"
    /bin/bash -e /pull_request.sh
fi