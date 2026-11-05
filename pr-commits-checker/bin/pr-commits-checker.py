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

# File name: pr-commits-checker.py
# Author: Popovici Iuliu-Antoniu
# Description:
#   Python script to analyze commits from a PR and check if they are signed and follows styling conventions
# Environment variables:
#   REPOSITORY: Repository name for the work in progress
#   GITHUB_TOKEN: Token with reads permission to check git log history
#   PR_ID: Pull request ID for the work in progress
#   FAIL_ON_FINDINGS: Condition to fail on findings or not

import os
from tabulate import tabulate
from html_to_markdown import convert
from actions_toolkit import core
from github import Github
from github import Auth

def parse_env():
    global REPOSITORY, GITHUB_TOKEN, PR_ID, FAIL_ON_FINDINGS

    REPOSITORY = os.environ["REPOSITORY"]
    GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
    PR_ID = os.environ["PR_ID"]
    FAIL_ON_FINDINGS = os.environ["FAIL_ON_FINDINGS"]

def check_pr_commits():
    global RETURN_ERR
    RETURN_ERR = False

    max_msg_len = 50
    max_body_len = 72

    auth = Auth.Token(GITHUB_TOKEN)
    github = Github(auth=auth)
    core.info(str(f"Logged in as user: {github.get_user().login}"))

    repo = github.get_repo(REPOSITORY)
    pull_request = repo.get_pull(int(PR_ID))
    pr_commits = pull_request.get_commits()
    findings = []
    try:
        for i, commit in enumerate(pr_commits):
            commit_sha = commit.commit.sha[0:7]
            core.info(f"Parse commit {commit_sha}")
            fail_cause = []

            # Separate sub-commits from main commit block
            commit_message = str(commit.commit.message).split("\n")
            
            # Check first block of commit - main message and next blank line
            if len(commit_message[0]) > max_msg_len:
                core.info(f"Main commit message bigger than {max_msg_len} characters!")
                fail_cause.append(f"Main commit message bigger than {max_msg_len} characters")
                RETURN_ERR = True
            if not commit_message[1] == "":
                core.info("No blank line between commit message and body!")
                fail_cause.append("No blank line between commit message and body")
                RETURN_ERR = True

            # Check last block of commit - signed by and assisted by, and store last index of middle block
            k = len(commit_message) - 1
            missing_last_blank = False
            if "Signed-off-by" not in commit_message[-1]:
                core.info("Commit not signed!")
                fail_cause.append("Commit not signed")
                RETURN_ERR = True
            for j in reversed(range(1, k)):
                if commit_message[j] != "" and "Assisted-by" not in commit_message[j] and not missing_last_blank:
                    if "Signed-off-by" in commit_message[j]:
                        core.info(f"Line: {j + 1} - Multiple signs!")
                        fail_cause.append(f"Line: {j + 1} - Multiple signs")
                        RETURN_ERR = True
                    else:
                        core.info("No blank line before signature and assists!")
                        fail_cause.append("No blank line before signature and assists")
                        # Prevent appending multiple times same message
                        missing_last_blank = True
                        RETURN_ERR = True
                if commit_message[j] == "":
                    # Re-store last index of middle block in case of change
                    k = j
                    break

            # Check middle block of commit - starting from 3rd line to end of last index of middle block
            for j in range(1, k):
                if len(commit_message[j]) > max_body_len:
                    # Ignore lines with URLs and identation
                    if not commit_message[j].startswith((" ", "-")) and not any(s in commit_message[j] for s in ("http", "https")):
                        core.info(f"Line: {j + 1} - Commit body message bigger than {max_body_len} characters!")
                        fail_cause.append(f"Line: {j + 1} - Commit body message bigger than {max_body_len} characters")
                        RETURN_ERR = True
            if len(fail_cause) > 0:
                finding_dict = {}
                finding_dict["nr"] = str(i + 1)
                finding_dict["sha"] = f":x:{commit_sha}"
                finding_dict["cause"] = '; '.join(fail_cause)
                findings.append(finding_dict)
    except Exception as e:
        core.set_failed(e)

    return findings

def export_md(findings):
    headers = ["Commit", "Sha", "Cause"]
    table = []
    
    try:
        if len(findings) == 0:
            core.info("No findings detected. Not generating the report.")
        else:
            core.info("Generate html report ...")
            for finding in findings:
                new_table = [finding["nr"], finding["sha"], finding["cause"]]
                table.append(new_table)
            html = tabulate(table, headers, tablefmt="html")

            core.info("Convert report to markdown ...")
            md = str(convert(html).content).replace("\_", "_")
            with open("pr_commits_checker.md", "w") as f:
                f.write("### :warning: Commits not following convention: \n\n")
                f.write(md)
    except Exception as e:
        core.set_failed(e)


def main():
    core.start_group("Parse environment variables")
    parse_env()
    core.end_group()

    core.start_group("Check github workspace")
    findings = check_pr_commits()
    core.end_group()

    core.start_group("Generate and export report to markdown")
    export_md(findings)
    core.end_group()

    if RETURN_ERR and FAIL_ON_FINDINGS == "true":
        core.set_failed("Commit message and body convention not followed!")

if __name__ == "__main__":
    main()