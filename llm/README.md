# llm

Bootstrap running an AI Agent reviewer inside GitHub Actions with real tools,
context and safety in mind.

Minimal Usage:
```

jobs:
  llm:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      checks: read # For CI/CD annotations
      pull-requests: read # For pull request comments

    steps:
      - uses: analogdevicesinc/shared-actions/llm@main
        id: llm
        with:
          ref: ${{ inputs.ref }}
          model: ${{ inputs.model || 'medium' }}
          prompt-file: ${{ env.prompt_file }}
          api-key: ${{ secrets.PORTKEY_API_KEY }}
          py-venv: ${{ env.py_venv }}
```
Deployed examples:

- https://github.com/analogdevicesinc/documentation/blob/main/.github/workflows/llm.yml
- https://github.com/analogdevicesinc/linux/blob/main/.github/workflows/llm.yml
- https://github.com/analogdevicesinc/br2-external/blob/main/.github/workflows/llm.yml

User guide documentation:
https://analogdevicesinc.github.io/documentation/contributing/ai.html#pull-request-reviewer

Full example template with self hosted runner, dual dispatch and call modes,
user prompt, python virtual enviroment, extra repository and post review to
pull request body:

```
name: LLM Agent
run-name: LLM run ${{ inputs.ref || github.ref }}

on:
  workflow_dispatch:
    inputs:
      ref:
        description: "The branch, tag, PR number, or SHA to checkout"
        required: false
        type: string
      prompt:
        description: "Prompt to use, overwrites the default"
        required: false
        type: string
        default: ""
      prompt-extra:
        description: "Extra prompt to concatenate"
        required: false
        type: string
        default: ""
      model:
        description: "Model size"
        type: choice
        default: medium
        options:
          - small
          - medium
          - large
      strategy:
        description: "Review strategy"
        type: choice
        default: commit
        options:
          - commit
          - files
  workflow_call:
    inputs:
      ref:
        required: false
        type: string
        default: ${{ github.ref }}
      prompt:
        required: false
        type: string
        default: ""
      prompt-extra:
        required: false
        type: string
        default: ""
      model:
        required: false
        type: string
        default: "medium"
      strategy:
        description: "Review strategy"
        type: string
        default: "commit"
    secrets:
      PORTKEY_API_KEY:
        required: true

jobs:
  llm:
    runs-on: ${{ vars.RUNNER != '' && fromJSON(vars.RUNNER) || 'ubuntu-latest' }}
    permissions:
      contents: read
      checks: read
      pull-requests: read

    outputs:
      pr: ${{ steps.llm.outputs.pr }}
      comment: ${{ steps.llm.outputs.comment }}

    steps:
      - name: Prepare prompt
        shell: bash
        run: |
          prompt_file=$(mktemp --suffix=.md)
          echo "prompt_file=$prompt_file" >> "$GITHUB_ENV"

          cat <<'EOF' > "$prompt_file"
          ${{ inputs.prompt }}
          EOF

          grep -q '[^[:space:]]' "$prompt_file" || \
          cat <<'EOF' > "$prompmain"
          # Run a deep review.

          Key rules to verify:
          - ...
          - ...

          Review priorities:
          1. ...
          2. ...

          Useful validation commands:
          ```sh
          make check
          ```

          cat <<'EOF' >> "$prompt_file"
          ${{ inputs.prompt-extra }}
          EOF

      - name: Prepare tools
        shell: bash
        run: |
          py_venv="$(mktemp -d)"
          echo "py_venv=$py_venv" >> "$GITHUB_ENV"

          python3 -m venv "$py_venv"
          source "$py_venv/bin/activate"
          python3 -m ensurepip --upgrade
          pip install --upgrade pip

      - name: Get some docs
        shell: bash
        run: |
          git clone https://github.com/... \
            --depth 1 --filter=blob:none --sparse -- docs
          git -C docs sparse-checkout set docs

      - uses: analogdevicesinc/shared-actions/llm@main
        id: llm
        with:
          ref: ${{ inputs.ref }}
          model: ${{ inputs.model || 'medium' }}
          prompt-file: ${{ env.prompt_file }}
          api-key: ${{ secrets.PORTKEY_API_KEY }}
          py-venv: ${{ env.py_venv }}

      - name: Clean-up
        if: always()
        shell: bash
        run: |
          rm -f "$prompt_file"
          rm -rf "$py_venv"
          rm -rf buildroot-docs

  pr-comment:
    runs-on: ubuntu-slim
    needs: llm
    permissions:
      pull-requests: write

    steps:
      - uses: analogdevicesinc/doctools/gh-pr-comment@action
        with:
          pr: ${{ needs.llm.outputs.pr }}
          body: ${{ needs.llm.outputs.comment }}

```
