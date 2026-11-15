# rules_multitool

An ergonomic approach to defining a single tool target that resolves to a matching os and CPU architecture variant of the tool.

## Usage

For a quickstart, see the [module example](examples/module/) or [workspace example](examples/workspace/).

Define a [lockfile](lockfile.schema.json) that references the tools to load:

```json
{
  "$schema": "https://raw.githubusercontent.com/theoremlp/rules_multitool/main/lockfile.schema.json",
  "tool-name": {
    "binaries": [
      {
        "kind": "file",
        "url": "https://...",
        "sha256": "sha256 of the file",
        "os": "linux|macos|windows",
        "cpu": "x86_64|arm64|riscv64"
      }
    ]
  }
}
```

The lockfile supports the following binary kinds:

- **file**: the URL refers to a file to download

  - `sha256`: the sha256 of the downloaded file
  - `headers`: (optional) a string dictionary of headers to pass to the downloader
  - `auth_patterns`: (optional) a string dictionary for use with .netrc files as in https://bazel.build/rules/lib/repo/http#http_file-auth_patterns

- **archive**: the URL referes to an archive to download, specify additional options:

  - `file`: executable file within the archive
  - `sha256`: the sha256 of the downloaded archive
  - `type`: (optional) the kind of archive, as in https://bazel.build/rules/lib/repo/http#http_archive-type
  - `headers`: (optional) a string dictionary of headers to pass to the downloader
  - `auth_patterns`: (optional) a string dictionary for use with .netrc files as in https://bazel.build/rules/lib/repo/http#http_archive-auth_patterns

- **pkg**: the URL refers to a MacOS pkg archive to download, specify additional options:

  - `file`: executable file within the archive
  - `sha256`: the sha256 of the downloaded pkg archive
  - `headers`: (optional) a string dictionary of headers to pass to the downloader
  - `auth_patterns`: (optional) a string dictionary for use with .netrc files as in https://bazel.build/rules/lib/repo/http#http_archive-auth_patterns

### Bazel Module Usage

Once your lockfile is defined, load the ruleset in your MODULE.bazel and create a hub that refers to your lockfile:

```python
bazel_dep(name = "rules_multitool", version = "0.0.0")

multitool = use_extension("@rules_multitool//multitool:extension.bzl", "multitool")
multitool.hub(lockfile = "//:multitool.lock.json")
use_repo(multitool, "multitool")
```

Tools may then be accessed using `@multitool//tools/tool-name`.

It's safe to call `multitool.hub(...)` multiple times, with multiple lockfiles. All lockfiles will be combined with a last-write-wins strategy.

Lockfiles defined across modules and applying to the same hub (including implicitly to the default "multitool" hub) will be combined such that the priority follows a breadth-first search originating from the root module.

It's possible to define multiple multitool hubs to group related tools together. To define an alternate hub:

```python
multitool.hub(hub_name = "alt_hub", lockfile = "//:other_tools.lock.json")
use_repo(multitool, "alt_hub")

# register the tools from this hub
register_toolchains("@alt_hub//toolchains:all")
```

These alternate hubs also combine lockfiles according to the hub_name and follow the same merging rules as the default hub.

### Workspace Usage

Instructions for using with WORKSPACE may be found in [release notes](https://github.com/theoremlp/rules_multitool/releases).

### Running tools in the current working directory

When running `@multitool//tools/tool-name`, Bazel will execute the tool at the root of the runfiles tree due to https://github.com/bazelbuild/bazel/issues/3325.

It's possible to workaround this:
- To run a tool in the current working directory, use the convenience target `@multitool//tools/[tool-name]:cwd`.
- To run a tool in the Bazel module or workspace root, use the convenience target `@multitool//tools/[tool-name]:workspace_root`.

Alternatively, consider using https://registry.build/github/buildbuddy-io/bazel_env.bzl to put tools on the `PATH`.

### Keeping Tools Up-to-Date

We provide a companion CLI [multitool](https://github.com/theoremlp/multitool) to help manage multitool lockfiles. The CLI supports basic updating of artifacts that come from GitHub releases, and may be extended in the future to support other common release channels.

See [our docs](docs/automation.md) on configuring a GitHub Action to check for updates and open PRs periodically.
