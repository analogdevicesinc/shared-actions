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
import re
from tabulate import tabulate
from actions_toolkit import core
from github import Github
from github import Auth

# Global constants
MAX_MSG_LEN = 50
MAX_BODY_LEN = 72
TRAILERS_REGEX = {
    "Signed-off-by:" : r"\s+.+\s+<.+@.+>",
    "Co-developed-by:" : r"\s+.+\s+<.+@.+>",
    "Suggested-by:": r"\s+.+\s+<.+@.+>",
    "Assisted-by:": r"\s.",
    "Co-authored-by:": r"\s+.+\s+<.+@.+>",
    "Co-Authored-By:": r"\s+.+\s+<.+@.+>",
    "Reviewed-by:": r"\s+.+\s+<.+@.+>",
    "Acked-by:": r"\s+.+\s+<.+@.+>",
    "Tested-by:": r"\s+.+\s+<.+@.+>",
    "Reported-by:": r"\s+.+\s+<.+@.+>",
    "Fixes:": r"\s.",
    "Closes:": r"\s.",
    "Resolves:": r"\s.",
    "Link:": r"\s+https?://\S+",
    "Cc:": r"\s+(.+\s+<.+@.+>|\S+@\S+)",
    "Depends-on:": r"\s.",
    "Jira:": r"\s+\S+"
}

def parse_env():
    global REPOSITORY, GITHUB_TOKEN, PR_ID, FAIL_ON_FINDINGS

    REPOSITORY = os.environ["REPOSITORY"]
    GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
    PR_ID = os.environ["PR_ID"]
    FAIL_ON_FINDINGS = os.environ.get("FAIL_ON_FINDINGS", "true")

def check_first_block(commitMessage: list, failCauses: list):
    """ Check first block of commit.
    Convention to be followed: message less than 50 characters, not empty and followed
    by a blank line.
    """
    if commitMessage[0].strip() == "":
        core.info("Main commit message does not exist!")
        failCauses.append("Main commit message does not exist")
    elif len(commitMessage[0]) > MAX_MSG_LEN:
        core.info(f"Main commit message bigger than {MAX_MSG_LEN} characters!")
        failCauses.append(f"Main commit message bigger than {MAX_MSG_LEN} characters")
    if len(commitMessage) > 1 and commitMessage[1] != "":
        core.info("No blank line between commit message and body!")
        failCauses.append("No blank line between commit message and body")

def check_last_block(commitMessage: list, failCauses: list, ltIndex: int):
    """ Check last block of commit.
    Convention to be followed: signatures exists, assists before signatures,
    trailers must be followed by the coresponding regex format and a blank
    space before trailers and body, if it exists. It stores signatures and assists
    index for covering assists over signatures convention
    """
    signature_index = 0
    assists_index = []
    for i in reversed(range(len(commitMessage))):
        if str(commitMessage[i]).startswith(tuple(TRAILERS_REGEX.keys())):
            ltIndex = i
            if "Assisted-by:" in commitMessage[i]:
                assists_index.append(i)     # Store assists indexes
            elif "Signed-off-by:" in commitMessage[i]:
                signature_index = i         # Store last signature index until found
            # Check pattern is followed after trailer
            regex_found = False
            for key, item in TRAILERS_REGEX.items():
                if re.match(rf"{key}{item}", commitMessage[i]):
                    regex_found = True
                    break
            if not regex_found:
                core.info(f"Line: {i + 1} - Trailer not followed by expected format!")
                failCauses.append(f"Line: {i + 1} - Trailer not followed by expected format")
        elif commitMessage[i] == "" or ltIndex < len(commitMessage):
            # Stop at blank line or at first non trailer line above the trailers
            break
    
    # Compare positions of last store signature and assists indexes
    for ai in assists_index:
        if ai > signature_index:
            core.info(f"Line: {ai + 1} - Assist needs to exists before signatures!")
            failCauses.append(f"Line: {ai + 1} - Assist needs to exists before signatures")
    if signature_index == 0:
        core.info("Commit not signed!")
        failCauses.append("Commit not signed")

    # Check blank line before last block - only if the commit has a body
    has_body = any(commitMessage[i] != "" for i in range(2, ltIndex))
    if has_body and ltIndex < len(commitMessage) and commitMessage[ltIndex - 1] != "":
        core.info("No blank line before trailers!")
        failCauses.append("No blank line before trailers")

    return ltIndex

def check_middle_block(commitMessage: list, failCauses, warnCauses: list, ltIndex: int):
    """ Check middle block of commit.
    Conventions to be followed: message per line should be less than maximum body message length,
    exceptions are idented lines or urls, but warnings are kept instead of failures.
    """
    for i in range(2, ltIndex):
        # Ignore empty lines and lines with URLs
        if commitMessage[i] == "" or "http://" in commitMessage[i] or "https://" in commitMessage[i]:
            continue
        if len(commitMessage[i]) > MAX_BODY_LEN:
            # Indentation is only a warning
            if commitMessage[i].startswith((" ", "-")):
                core.warning(f"Line: {i + 1} - Indented line bigger than {MAX_BODY_LEN} characters!")
                warnCauses.append(f"Line: {i + 1} - Indented line bigger than {MAX_BODY_LEN} characters")
            else:
                core.info(f"Line: {i + 1} - Commit body message bigger than {MAX_BODY_LEN} characters!")
                failCauses.append(f"Line: {i + 1} - Commit body message bigger than {MAX_BODY_LEN} characters")

def generate_commit_status(findings: list, failCauses: list, warnCauses: list, commitSha: any, nCommit: int):
    """ Generate commit status methods.
    It extracts the failure and/or warnings causes if exists, and stores them with the number
    of commit, sha and the lists of causes as a dictionary then in the final list of findings
    """
    global RETURN_ERR

    if len(failCauses) > 0 or len(warnCauses) > 0:
        if len(failCauses) > 0:
            RETURN_ERR = True
        finding_dict = {}
        finding_dict["nr"] = str(nCommit + 1)
        finding_dict["sha"] = f":x:{commitSha}" if len(failCauses) > 0 else f":warning:{commitSha}"
        finding_dict["cause"] = '; '.join(failCauses + warnCauses)
        findings.append(finding_dict)

def check_pr_commits():
    global RETURN_ERR
    RETURN_ERR = False

    auth = Auth.Token(GITHUB_TOKEN)
    github = Github(auth=auth)

    repo = github.get_repo(REPOSITORY)
    pull_request = repo.get_pull(int(PR_ID))
    pr_commits = pull_request.get_commits()
    findings = []
    try:
        for i, commit in enumerate(pr_commits):
            commit_sha = commit.commit.sha[0:7]
            core.info(f"Parse commit {commit_sha}")
            fail_causes = []
            warn_causes = []

            # Separate sub-commits from main commit block
            # Normalize CRLF and drop trailing newlines
            commit_message = str(commit.commit.message).replace("\r\n", "\n").rstrip("\n").split("\n")

            # Start storing the index of last trailer
            lt_index = len(commit_message)

            # Check first block of commit - main message and next blank line
            check_first_block(commit_message, fail_causes)

            # Check last block of commit
            lt_index = check_last_block(commit_message, fail_causes, lt_index)

            # Check middle block of commit - starting from 3rd line to first index of last block
            check_middle_block(commit_message, fail_causes, warn_causes, lt_index)

            # Generate the status of current commit
            generate_commit_status(findings, fail_causes, warn_causes, commit_sha, i)
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
            core.info("Generate markdown report ...")
            for finding in findings:
                new_table = [finding["nr"], finding["sha"], finding["cause"]]
                table.append(new_table)
            md = tabulate(table, headers, tablefmt="github")
            with open("pr_commits_checker.md", "w") as f:
                f.write("### :warning: Commits not following convention: \n\n")
                f.write(md)
                f.write("\n")
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
