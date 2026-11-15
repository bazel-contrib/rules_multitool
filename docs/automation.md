# GitHub Action Automation for Updating Tools

## Using rules_multitool

Configure your multitool lockfile to supply the multitool CLI. The action below assumes the tool name is set to "multitool".

Then, make sure you have a GitHub Application to supply a token for creating a PR to your repository. The application will generally need 'Read & Write' on 'Pull Requests'. Ensure that your repository has access to two secrets related to your application:

1.  AUTOMATION_APP_ID: the application's integer id (visible to administrators of the application at the top of the General page)
2.  AUTOMATION_PRIVATE_KEY: a private key generated in the 'Private Keys' section of the General page

Create an action as follows, be sure to update the LOCKFILE environment variable to match your lockfile location, adjust secret names if they differ from the names above, and to update the committer in the final step.

```yaml
name: Periodic - Update Multitool Versions
on:
  workflow_dispatch: {}
  schedule:
    # run every hour on the 5 between 9am and 5pm (4am and 12pm UTC), M-F
    - cron: "5 14-22 * * 1-5"
jobs:
  update-requirement:
    name: Update Multitool Versions
    runs-on: ubuntu-latest
    permissions:
      contents: read
    # disable running on anything but main
    if: ${{ github.ref == 'refs/heads/main' }}
    env:
      LOCKFILE: ./multitool.lock.json
    steps:
      - name: Get Token
        id: app-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.AUTOMATION_APP_ID }}
          private-key: ${{ secrets.AUTOMATION_PRIVATE_KEY }}
      - uses: actions/checkout@v4
        with:
          token: ${{ steps.app-token.outputs.token }}

      - name: Find Updates and Render Lockfile
        run: bazel run --run_in_cwd @multitool//tools/multitool -- --lockfile "$LOCKFILE" update

      - name: Commit Changes
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          BRANCH_NAME: "automation/update-multitool-lockfile"
        run: |
          if [[ -n "$(git diff "$LOCKFILE")" ]]
          then
            git config --local user.name 'Automation'
            git config --local user.email 'app-name[bot]@users.noreply.github.com'
            git checkout -b "${BRANCH_NAME}"
            git add "$LOCKFILE"
            git commit -m "Update Multitool Versions
            
            Updated with [update-multitool](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}) by *${GITHUB_ACTOR}*
            "
            git push origin "${BRANCH_NAME}" -f
            gh pr create --fill --label "automerge" >> "$GITHUB_STEP_SUMMARY"
          fi
```

## Using the multitool CLI directly

An alternative approach is to use the multitool CLI directly by downloading it.

The preparation for this is largely the same, but you may skip including the multitool CLI in your lockfile.

```yaml
name: Periodic - Update Multitool Versions
on:
  workflow_dispatch: {}
  schedule:
    # run every hour on the 5 between 9am and 5pm (4am and 12pm UTC), M-F
    - cron: "5 14-22 * * 1-5"
jobs:
  update-requirement:
    name: Update Multitool Versions
    runs-on: ubuntu-latest
    permissions:
      contents: read
    # disable running on anything but main
    if: ${{ github.ref == 'refs/heads/main' }}
    env:
      LOCKFILE: ./multitool.lock.json
    steps:
      - name: Get Token
        id: app-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.AUTOMATION_APP_ID }}
          private-key: ${{ secrets.AUTOMATION_PRIVATE_KEY }}
      - uses: actions/checkout@v4
        with:
          token: ${{ steps.app-token.outputs.token }}
      - name: Download and Extract Latest Multitool
        run: wget -O- https://github.com/theoremlp/multitool/releases/latest/download/multitool-x86_64-unknown-linux-gnu.tar.xz | tar --strip-components=1 -xJf -

      - name: Find Updates and Render Lockfile
        run: ./multitool --lockfile "$LOCKFILE" update

      - name: Commit Changes
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          BRANCH_NAME: "automation/update-multitool-lockfile"
        run: |
          if [[ -n "$(git diff "$LOCKFILE")" ]]
          then
            git config --local user.name 'Automation'
            git config --local user.email 'app-name[bot]@users.noreply.github.com'
            git checkout -b "${BRANCH_NAME}"
            git add "$LOCKFILE"
            git commit -m "Update Multitool Versions
            
            Updated with [update-multitool](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}) by *${GITHUB_ACTOR}*
            "
            git push origin "${BRANCH_NAME}" -f
            gh pr create --fill --label "automerge" >> "$GITHUB_STEP_SUMMARY"
          fi
```
