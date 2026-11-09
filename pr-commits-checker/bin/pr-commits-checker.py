#!/usr/bin/env python3

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

import os
import re
from tabulate import tabulate
from actions_toolkit import core
from github import Github, Auth

MAX_MSG_LEN = 50
MAX_BODY_LEN = 72
SIGNOFF_PATTERN = re.compile(r'Signed-off-by:\s+.+\s+<.+@.+>')
TRAILERS = ["Signed-off-by:", "Assisted-by:", "Co-authored-by:", "Reviewed-by:",
            "Acked-by:", "Tested-by:", "Reported-by:", "Fixes:", "Closes:", "Resolves:", "Link:", "Cc:"]


def parse_env():
    global REPOSITORY, GITHUB_TOKEN, PR_ID, FAIL_ON_FINDINGS
    REPOSITORY = os.environ["REPOSITORY"]
    GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
    PR_ID = os.environ["PR_ID"]
    FAIL_ON_FINDINGS = os.environ.get("FAIL_ON_FINDINGS", "true")


def is_trailer(line):
    return any(line.startswith(t) for t in TRAILERS)


def check_pr_commits():
    global RETURN_ERR
    RETURN_ERR = False

    auth = Auth.Token(GITHUB_TOKEN)
    github = Github(auth=auth)
    core.info(f"Logged in as user: {github.get_user().login}")

    repo = github.get_repo(REPOSITORY)
    pr_commits = repo.get_pull(int(PR_ID)).get_commits()
    findings = []

    for i, commit in enumerate(pr_commits):
        sha = commit.commit.sha[0:7]
        core.info(f"Parse commit {sha}")
        fail_cause, warn_cause = [], []
        msg = str(commit.commit.message).split("\n")

        # Header length
        if len(msg[0]) > MAX_MSG_LEN:
            fail_cause.append(f"Main commit message bigger than {MAX_MSG_LEN} characters")

        # Blank line after header
        if len(msg) > 1 and msg[1] != "":
            fail_cause.append("No blank line between commit message and body")

        # Valid Signed-off-by
        if not any(SIGNOFF_PATTERN.search(line) for line in msg):
            fail_cause.append("Commit not signed")

        # Find trailer start
        trailer_start = len(msg)
        for j in reversed(range(len(msg))):
            if is_trailer(msg[j]):
                trailer_start = j
            elif msg[j] == "":
                break
            elif trailer_start < len(msg):
                break

        # Check body exists and blank before trailers
        has_body = any(msg[j] != "" and not is_trailer(msg[j]) for j in range(2, trailer_start))
        if has_body and trailer_start < len(msg) and msg[trailer_start - 1] != "":
            fail_cause.append("No blank line before trailers")

        # Body line lengths
        for j in range(2, trailer_start):
            line = msg[j]
            if not line or is_trailer(line) or "http://" in line or "https://" in line:
                continue
            if len(line) > MAX_BODY_LEN:
                if line.startswith((" ", "-")):
                    warn_cause.append(f"Line: {j + 1} - Indented line bigger than {MAX_BODY_LEN} characters")
                else:
                    fail_cause.append(f"Line: {j + 1} - Commit body message bigger than {MAX_BODY_LEN} characters")

        if fail_cause or warn_cause:
            RETURN_ERR = RETURN_ERR or bool(fail_cause)
            findings.append({
                "nr": str(i + 1),
                "sha": f":x:{sha}" if fail_cause else f":warning:{sha}",
                "cause": "; ".join(fail_cause + warn_cause)
            })
            for e in fail_cause:
                core.info(f"  {e}")
            for w in warn_cause:
                core.warning(f"  {w}")

    return findings


def export_md(findings):
    if not findings:
        core.info("No findings detected. Not generating the report.")
        return
    core.info("Generate markdown report ...")
    table = [[f["nr"], f["sha"], f["cause"]] for f in findings]
    with open("pr_commits_checker.md", "w") as f:
        f.write("### :warning: Commits not following convention:\n\n")
        f.write(tabulate(table, ["Commit", "Sha", "Cause"], tablefmt="github"))
        f.write("\n")


def main():
    core.start_group("Parse environment variables")
    parse_env()
    core.end_group()

    core.start_group("Check PR commits")
    findings = check_pr_commits()
    core.end_group()

    core.start_group("Generate and export report to markdown")
    export_md(findings)
    core.end_group()

    if RETURN_ERR and FAIL_ON_FINDINGS == "true":
        core.set_failed("Commit message and body convention not followed!")


if __name__ == "__main__":
    main()
