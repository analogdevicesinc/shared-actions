#!/bin/bash

# Copyright 2026 Analog Devices, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

############################################################################
# If the current build is not a pull request and it is on main the 
# documentation will be pushed to the gh-pages branch if changes occurred
# since the last version that was pushed
############################################################################

mkdir -p ${DOCS_DIR}/build
cd ${DOCS_DIR}/build
cmake ..
make $ARGS
ret_code=$?
if [[ "$ret_code" != 0 ]]; then
    echo "Documentation incomplete or errors in the generation of it have occured!"
    exit 1
fi
echo "Documentation was generated successfully!"

cd ${WORK_DIR}

MAIN_COMMIT=$(git rev-parse --short HEAD)

echo "Running Github docs update on commit '$MAIN_COMMIT'"

git config --global user.email "cse-ci-notifications@analog.com"
git config --global user.name "CSE-CI"
git fetch --depth 1 origin +refs/heads/gh-pages:gh-pages
git checkout --force gh-pages

rm -rf ${DEPS_DIR}
cp -R ${DOCS_DIR}/build/doxygen_doc/html/* ${WORK_DIR}
rm -rf ${DOCS_DIR}

git add --all .

if git diff --cached --quiet; then
    echo "Documentation already up to date - no changes to commit"
else
    git commit -m "Update documentation to ${MAIN_COMMIT:0:7}"
    if [[ "$PUBLISH" == "true" ]]; then
        if [ -n "$GITHUB_DOC_TOKEN" ] ; then
            git push https://${GITHUB_DOC_TOKEN}@github.com/${REPO_SLUG} gh-pages
        else
            git push origin gh-pages
        fi
        echo "Documentation updated!"
    else
        echo "Publishing to github pages disabled!"
    fi
fi
