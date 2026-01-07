"multitool module extension"

load("//multitool/private:multitool.bzl", _hub = "bzlmod_hub")

_DEFAULT_HUB_NAME = "multitool"

hub = tag_class(
    attrs = {
        "hub_name": attr.string(default = _DEFAULT_HUB_NAME),
        "lockfile": attr.label(mandatory = True, allow_single_file = True),
    },
)

def _extension(module_ctx):
    lockfiles = {
        _DEFAULT_HUB_NAME: [],
    }

    root_module_direct_deps = {}
    root_module_direct_dev_deps = {}

    for mod in reversed(module_ctx.modules):
        for h in mod.tags.hub:
            if h.hub_name in lockfiles:
                lockfiles[h.hub_name].append(h.lockfile)
            else:
                lockfiles[h.hub_name] = [h.lockfile]

            if mod.is_root:
                (root_module_direct_dev_deps if module_ctx.is_dev_dependency(h) else root_module_direct_deps)[h.hub_name] = 1

    # ensure _DEFAULT_HUB_NAME is present in non-dev and dev deps
    # when non-dev and dev deps are non-empty.
    if len(root_module_direct_deps) > 0:
        root_module_direct_deps[_DEFAULT_HUB_NAME] = 1
    if len(root_module_direct_dev_deps) > 0:
        root_module_direct_dev_deps[_DEFAULT_HUB_NAME] = 1

    for lockfile_name, lockfile_list in lockfiles.items():
        _hub(
            name = lockfile_name,
            lockfiles = lockfile_list,
            module_ctx = module_ctx,
        )

    return module_ctx.extension_metadata(
        root_module_direct_deps = root_module_direct_deps.keys(),
        root_module_direct_dev_deps = root_module_direct_dev_deps.keys(),
        reproducible = True,  # repo state is only a function of the lockfile
    )

multitool = module_extension(
    implementation = _extension,
    tag_classes = {
        "hub": hub,
    },
)
