"""
multitool

Multitool takes as input a JSON lockfile and emits the following repos:

 - [hub].[tool].[os]_[cpu]:
     This repository holds the per-tool os/cpu binary in the provided lockfile.

     The structure of this repo is:
       tools/
         [tool-name]/
           BUILD.bazel            (export all *_executable files)
           [os]_[cpu]_executable  (a downloaded file or a symlink to a file in a
                                   downloaded and extracted archive)

 - [hub]:
     This repository holds toolchain definitions for all tools in the provided
     lockfile(s), as well as an executable tool target that will pick the
     appropriate toolchain.

     The structure of this repo is:
       toolchains/
         BUILD.bazel      (a single file containing all declared toolchains for easy registration)
       tools/
         [tool-name]/
           BUILD.bazel    (declares the toolchain_type and the executable tool target)
           tool.bzl       (scaffolding for the tool target and toolchain declarations in toolchains/BUILD.bazel)
       toolchain_info.bzl (common scaffolding for toolchain declarations)
       tools.bzl          (a file containing one utility method, "register_tools", to support WORKSPACE users)

       (additional BUILD.bazel and a WORKSPACE file are included as required by Bazel)

To keep things orderly, we keep all the toolchain Bazel goo in the [hub] repo and only stash
the binaries in the [hub].[tool].[os]_[cpu] repos. It's a conscious decision not to place some
fragments of the toolchain definitions in the latter repos to make the dependencies run exactly
one way:
    [hub] -> [hub].[tool].[os]_[cpu].

This implementation depends on rendering a number of templates, which are defined in sibling
folders and managed by the templates starlark file.

Note that we intend to support both bzlmod and non-bzlmod setups, so `hub` intentionally avoids
a register_toolchains call.
"""

load("@bazel_features//:features.bzl", "bazel_features")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_netrc", "read_user_netrc", "use_netrc")
load(":lockfile.bzl", "lockfile")
load(":templates.bzl", "templates")

def _get_auth(rctx, urls, auth_patterns):
    "Returns an auth dict for the provided list of URLs."
    if "NETRC" in rctx.os.environ:
        netrc = read_netrc(rctx, rctx.os.environ["NETRC"])
    else:
        netrc = read_user_netrc(rctx)
    return use_netrc(netrc, urls, auth_patterns)

def _feature_sensitive_args(binary):
    args = {}
    if bazel_features.external_deps.download_has_headers_param:
        args["headers"] = binary.get("headers", {})

    return args

def _extension(os):
    if os == "windows":
        return ".exe"
    return ""

def _download_extract_tool(rctx, tool_name, binary):
    reproducible = True

    target_filename = "{os}_{cpu}_executable{ext}".format(
        cpu = binary["cpu"],
        os = binary["os"],
        ext = _extension(binary["os"]),
    )
    target_executable = "tools/{tool_name}/{filename}".format(
        tool_name = tool_name,
        filename = target_filename,
    )

    if binary["kind"] == "file":
        rctx.download(
            url = binary["url"],
            sha256 = binary["sha256"],
            output = target_executable,
            executable = True,
            auth = _get_auth(rctx, [binary["url"]], binary.get("auth_patterns", {})),
            **_feature_sensitive_args(binary)
        )
    elif binary["kind"] == "archive":
        archive_path = "tools/{tool_name}/{os}_{cpu}_archive".format(
            tool_name = tool_name,
            cpu = binary["cpu"],
            os = binary["os"],
        )

        rctx.download_and_extract(
            url = binary["url"],
            sha256 = binary["sha256"],
            output = archive_path,
            type = binary.get("type", ""),
            auth = _get_auth(rctx, [binary["url"]], binary.get("auth_patterns", {})),
            **_feature_sensitive_args(binary)
        )

        # link to the executable
        archive_file = "{archive_path}/{file}".format(archive_path = archive_path, file = binary["file"])
        if not rctx.path(archive_file).exists:
            fail("{tool_name} ({os}, {cpu}): Cannot find {file} in archive from {url}".format(
                tool_name = tool_name,
                os = binary["os"],
                cpu = binary["cpu"],
                file = archive_file,
                url = binary["url"],
            ))
        rctx.symlink(archive_file, target_executable)
    elif binary["kind"] == "pkg":
        # Binaries of kind "pkg" behave differently depending on the presence of pkgutil.
        reproducible = False

        # Check if pkgutil is on the path, and if not fail silently.
        # repository rules execute irrespective of platform/OS, so this
        # check is required for `pkg_archive` to not fail on Linux.
        pkgutil_cmd = rctx.which("pkgutil")
        if not pkgutil_cmd:
            return reproducible

        archive_path = "tools/{tool_name}/{os}_{cpu}_pkg".format(
            tool_name = tool_name,
            cpu = binary["cpu"],
            os = binary["os"],
        )

        rctx.download(
            url = binary["url"],
            sha256 = binary["sha256"],
            output = archive_path + ".pkg",
            auth = _get_auth(rctx, [binary["url"]], binary.get("auth_patterns", {})),
            **_feature_sensitive_args(binary)
        )

        rctx.execute([pkgutil_cmd, "--expand-full", archive_path + ".pkg", archive_path])

        # link to the executable
        archive_file = "{archive_path}/{file}".format(archive_path = archive_path, file = binary["file"])
        if not rctx.path(archive_file).exists:
            fail("{tool_name} ({os}, {cpu}): Cannot find {file} in archive from {url}".format(
                tool_name = tool_name,
                os = binary["os"],
                cpu = binary["cpu"],
                file = archive_file,
                url = binary["url"],
            ))
        rctx.symlink(archive_file, target_executable)
    else:
        fail("Unknown 'kind' {kind}".format(kind = binary["kind"]))

    templates.tool_tool(rctx, tool_name, "BUILD.bazel", {"{target_filename}": target_filename})

    return reproducible

def _tool_repo_impl(rctx):
    reproducible = _download_extract_tool(rctx, rctx.attr.tool_name, json.decode(rctx.attr.binary))
    templates.tool(rctx, "tools/BUILD.bazel")
    templates.tool(rctx, "BUILD.bazel")

    # Bazel <8.3.0 lacks rctx.repo_metadata
    if not hasattr(rctx, "repo_metadata"):
        return None

    return rctx.repo_metadata(reproducible = reproducible)

tool_repo = repository_rule(
    attrs = {
        "tool_name": attr.string(),
        "binary": attr.string(),
        "os": attr.string(),
        "cpu": attr.string(),
    },
    implementation = _tool_repo_impl,
)

def _multitool_hub_impl(rctx):
    tools = lockfile.load_defs(rctx, rctx.attr.lockfiles)

    loads = []
    defines = []

    for tool_name, tool in lockfile.sorted_defs(tools):
        toolchains = []

        for binary in tool["binaries"]:
            toolchains.append('\n    declare_toolchain(name="{name}", os="{os}", cpu="{cpu}", toolchain_type=_TOOLCHAIN_TYPE)'.format(
                name = tool_name,
                cpu = binary["cpu"],
                os = binary["os"],
            ))

        templates.hub_tool(rctx, tool_name, "BUILD.bazel")
        templates.hub_tool(rctx, tool_name, "tool.bzl", {
            "{toolchains}": "\n".join(toolchains),
        })

        clean_name = tool_name.replace("-", "_")
        loads.append('load("//tools/{tool_name}:tool.bzl", declare_{clean_name}_toolchains = "declare_toolchains")'.format(
            tool_name = tool_name,
            clean_name = clean_name,
        ))
        defines.append("declare_{clean_name}_toolchains()".format(clean_name = clean_name))

    templates.hub(rctx, "BUILD.bazel")
    templates.hub(rctx, "toolchain_info.bzl", {
        "{hub_name}": rctx.attr.name,
    })
    templates.hub(rctx, "tools/BUILD.bazel")
    templates.hub(rctx, "toolchains/BUILD.bazel", {
        "{loads}": "\n".join(loads),
        "{defines}": "\n".join(defines),
    })

    # workspace compat & list of all tools
    templates.hub(rctx, "tools.bzl", templates.tools_substitutions(rctx.attr.name, tools))

    # Bazel <8.3.0 lacks rctx.repo_metadata
    if not hasattr(rctx, "repo_metadata"):
        return None

    return rctx.repo_metadata(reproducible = True)

_multitool_hub = repository_rule(
    attrs = {
        "lockfiles": attr.label_list(mandatory = True, allow_files = True),
    },
    implementation = _multitool_hub_impl,
)

def bzlmod_hub(name, lockfiles, module_ctx):
    """
    Creates a multitool hub for bzlmod.

    Args:
       name: name of the hub
       lockfiles: a list of lockfile labels containing multitool lockfiles
       module_ctx: a valid module_ctx instance
    """

    tools = lockfile.load_defs(module_ctx, lockfiles)
    for tool_name, tool in lockfile.sorted_defs(tools):
        for binary in tool["binaries"]:
            tool_repo(
                name = "{name}.{tool_name}.{os}_{cpu}".format(
                    name = name,
                    tool_name = tool_name,
                    os = binary["os"],
                    cpu = binary["cpu"],
                ),
                tool_name = tool_name,
                binary = json.encode(binary),
            )

    _multitool_hub(name = name, lockfiles = lockfiles)

def workspace_hub(name, lockfiles):
    """
    Creates a multitool hub for non-bzlmod.

    Args:
       name: name of the hub
       lockfiles: a list of lockfile labels containing multitool lockfiles
    """

    _multitool_hub(name = name, lockfiles = lockfiles)
