#!/bin/env python3

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

# File name: include-guards-checker.py
# Author: Popovici Iuliu-Antoniu
# Description:
#   Python script to check if the convention for include guards are followed in .c header files
#   and create a report with the findings.
# Environment variables:
#   WORKSPACE: Absolute path of the working directory containing the files to be checked. Default .
#   FILES: List of header files to be check, separated by ','. Relative to the WORKSPACE

import os
from tabulate import tabulate
from html_to_markdown import convert
from actions_toolkit import core

def parse_env():
    global WORKSPACE, FILES, FAIL_ON_FINDINGS

    WORKSPACE = os.environ["WORKSPACE"]
    FILES = os.environ["FILES"]
    FAIL_ON_FINDINGS = os.environ["FAIL_ON_FINDINGS"]

def check_include_guards():
    global RETURN_ERR
    RETURN_ERR = False

    os.chdir(WORKSPACE)
    findings = []

    try:
        if FILES:
            files = str(FILES).split(",")
            for header in files:
                path = os.path.join(WORKSPACE, header)
                # Convert file path name to NAME_H_ convention
                file_name = str(path.split("/")[-1]).upper().replace(".", "_") + "_"
                core.info(f"Checking {path}")
                with open(path, "r") as f:
                    lines = f.readlines()
                    # Remove trailing empty lines to correctly identify the closing #endif
                    while lines and lines[-1].strip() == "":
                        lines.pop()
                    ifndef_main = False
                    ifndef_extra = 0
                    define_main = False
                    endif_main = False
                    endif_extra = 0
                    def_content = ""
                    fail_cause = ""
                    fail_status = ""
                    bcomment_start = False      # block comment start marker

                    for i,line in enumerate(lines):
                        # Check if it's the start of a block comment
                        if line.startswith("/*") and not bcomment_start:
                            bcomment_start = True
                        if bcomment_start:     
                            if str(line[len(line) - 3:]).rstrip() == "*/":
                                bcomment_start = False
                            continue
                        # Check if it's the start of include guards, otherwise count it
                        if line.startswith("#ifndef"):
                            if not ifndef_main:
                                ifndef_main = True
                                def_content = line.split(" ")[1].strip()
                                if def_content != file_name:
                                    fail_cause = "Naming convention not followed: #ifndef NAME_H_"
                                    fail_status = ":warning:"
                                # Check the definition name to match the start of include guards
                                if str(lines[i + 1]).rstrip() != f"#define {def_content}":
                                    fail_cause = "Naming convention not followed: #define NAME_H_"
                                    fail_status = ":x:"
                                    RETURN_ERR = True
                                    break
                                else:
                                    define_main = True
                                    i = i + 1
                            else:
                                ifndef_extra += 1
                            continue
                        # Check if another line of code starts instead of include guards
                        if line.strip() and not ifndef_main:
                            fail_cause = "Include guards not found"
                            fail_status = ":x:"
                            RETURN_ERR = True
                            break
                        # Check if it's the end of include guards, otherwise count it
                        elif line.startswith("#endif"):
                            if i == len(lines) - 1:
                                endif_main = True
                            else:
                                endif_extra += 1
                            # In case there are extra endifs or include endif is before the end of the file,
                            # it means the start of include guards ended prematurely
                            if endif_extra > ifndef_extra:
                                fail_cause = "Include guards finished prematurely"
                                fail_status = ":x:"
                                RETURN_ERR = True
                                break

                # Append finding in case include not found or naming convention not followed
                if False in [ifndef_main, define_main, endif_main] or fail_cause != "":
                    core.info(f"Include guards convention not followed in: {header}")
                    finding_dict = {}
                    finding_dict["file"] = f"{fail_status} {header}"
                    finding_dict["cause"] = fail_cause
                    findings.append(finding_dict)
                else:
                    core.info("OK")
    except Exception as e:
        core.set_failed(e)
    
    return findings

def export_md(findings):
    table = []
    table_headers = ["File", "Cause"]

    try:
        if findings:
            core.info("Generating report...")
            for finding in findings:
                new_table = [finding["file"], finding["cause"]]
                table.append(new_table)
            html = tabulate(table, table_headers, tablefmt="html")
            
            md = str(convert(html).content).replace("\_", "_")
            with open("include_guards_findings.md", "w") as f:
                f.write("### :warning: Header files not following include guards convention:\n\n")
                f.write(md)
        else:
            core.info("All files have include guards")
    except Exception as e:
        core.set_failed(e)

def main():
    core.start_group("Parse environment variables")
    parse_env()
    core.end_group()

    core.start_group("Check header files")
    findings = check_include_guards()
    core.end_group()

    core.start_group("Generate and export report to markdown")
    export_md(findings)
    core.end_group()

    if RETURN_ERR and FAIL_ON_FINDINGS == "true":
        core.set_failed("Header files without include guards found!")

if __name__ == "__main__":
    main()
