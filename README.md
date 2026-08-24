# neorg-new

A Neorg plugin that adds the `:Neorg new`, `:Neorg new-from-template`, `:Neorg fork`,
`:Neorg fork-from-template` and `:Neorg parent` commands for quickly creating new `.norg`
files (and navigating back to the parent of a forked note) with automatically generated
content (and optional metadata).

## Installation

Install the plugin with your preferred package manager and load it inside your
Neorg setup. The module requires `core.dirman` to be loaded. Optionally load
`core.esupports.metagen` with `type = "auto"` or `type = "empty"` to enable
automatic metadata injection into new files.

### lazy.nvim

```lua
{
    "nvim-neorg/neorg",
    dependencies = {
        "brglng/neorg-new",
    },
    config = function()
        require("neorg").setup({
            load = {
                ["core.defaults"] = {},
                ["core.dirman"] = {
                    config = {
                        workspaces = {
                            notes = "~/notes",
                        },
                        default_workspace = "notes",
                    },
                },
                ["core.esupports.metagen"] = {
                    config = {
                        -- Set to "auto" or "empty" to enable metadata injection.
                        -- If omitted (or set to "none"), no metadata is injected.
                        type = "auto",
                    },
                },
                ["external.new"] = {
                    config = {
                        -- see Configuration below
                    },
                },
            },
        })
    end,
}
```

## Usage

```
:Neorg new [arg1] [arg2] ...
:Neorg new-from-template <template_name> [arg1] [arg2] ...
:Neorg fork [arg1] [arg2] ...
:Neorg fork-from-template <template_name> [arg1] [arg2] ...
:Neorg parent
```

For `:Neorg new` and `:Neorg fork`, one or more arguments are recommended (the default
callbacks require at least one). The arguments are forwarded to the `title`, `filename`,
and `template` callbacks to generate the respective values for the new file.

For `:Neorg new-from-template` and `:Neorg fork-from-template`, the first argument is the
**template name** passed as the first parameter to the `template` callback; the remaining
arguments are treated the same as with `:Neorg new`/`:Neorg fork`.

The `fork` subcommands behave exactly like their `new` counterparts, with two differences:
they are **only available inside a `.norg` file**, which is then used as the parent of the
forked note, and they **require metadata injection** (`core.esupports.metagen` with
`type = "auto"` or `type = "empty"`) to record the parent. A forked file additionally
records a `parent` field inside its `@document.meta` block holding the path of the parent
file relative to the root of the current workspace (e.g. `subdir/my-parent`). If metadata
injection is disabled, `:Neorg fork` fails with an error instead of creating a file.

The `parent` subcommand opens the parent of the current `.norg` file, as recorded in its
`parent` metadata field. It is only available inside a `.norg` file and fails with an error
if the current file carries no `parent` field.

By default:

- The **title** is formed by capitalizing the first letter of each argument and
  joining them with a single space.
- The **filename** is a timestamp formatted as `%Y%m%d%H%M%S` (e.g.
  `20240824233008`), with a `.norg` extension appended.
- The **heading** placed at the top of the file is the same as the title.

**Example:**

```
:Neorg new my meeting notes
```

This creates `20240824233008.norg` (a `%Y%m%d%H%M%S` timestamp) in the current
(or configured) workspace,
and prepends the heading `* My Meeting Notes` at the top of the file. If
`core.esupports.metagen` is loaded with `type = "auto"` or `type = "empty"`,
a `@document.meta` block with the `title` field set to `My Meeting Notes` is
also injected.

## Configuration

```lua
["external.new"] = {
    config = {
        -- Which workspace to use for new files.
        -- If nil, the current workspace is used.
        workspace = nil,

        -- Callback that receives the subcommand arguments as a table and
        -- returns the title string written into @document.meta.
        -- Default: capitalize the first letter of each argument and join
        -- with a single space (e.g. {"my", "note"} -> "My Note").
        -- (Used by `new`, `new-from-template`, `fork` and `fork-from-template`.)
        title = function(args)
            return table.concat(vim.tbl_map(function(s)
                return vim.fn.toupper(vim.fn.strcharpart(s, 0, 1)) .. vim.fn.strcharpart(s, 1)
            end, args), " ")
        end,

        -- Callback that receives the subcommand arguments as a table and
        -- returns the file path (with the .norg extension).
        -- The path may contain subfolder components; any missing parent
        -- directories are created automatically.
        -- Default: the current timestamp formatted as %Y%m%d%H%M%S
        -- (e.g. "20240824233008" -> "20240824233008.norg").
        -- (Used by `new`, `new-from-template`, `fork` and `fork-from-template`.)
        filename = function(args)
            return os.date("%Y%m%d%H%M%S")
        end,

        -- Callback that receives the template name (nil when using
        -- `:Neorg new`/`:Neorg fork`, or a string when using
        -- `:Neorg new-from-template`/`:Neorg fork-from-template`) and
        -- the subcommand arguments as a table, and returns a list of strings
        -- (lines) to insert into the new file.
        -- Default: a single top-level heading formed by capitalizing the
        -- first letter of each argument and joining with a single space.
        -- Set to nil to insert no additional content.
        template = function(name, args)
            local heading = table.concat(vim.tbl_map(function(s)
                return vim.fn.toupper(vim.fn.strcharpart(s, 0, 1)) .. vim.fn.strcharpart(s, 1)
            end, args), " ")
            return { "* " .. heading }
        end,
    },
},
```

### Notes on metadata

For `:Neorg new`/`:Neorg new-from-template`, metadata injection is **optional**. When
`core.esupports.metagen` is loaded and its `type` option is set to `"auto"` or `"empty"`,
a `@document.meta` block is injected into each new file with the `title` field set to the
value returned by the `title` callback. When `core.esupports.metagen` is not loaded, or its
`type` is set to `"none"`, no metadata block is generated and the `title` callback is not
called.

For forked files (created with `:Neorg fork` or `:Neorg fork-from-template`), metadata
injection is **required**: the command fails with an error if `core.esupports.metagen` is
not loaded or its `type` is not `"auto"`/`"empty"`. When enabled, an additional `parent`
field is written into the `@document.meta` block holding the path of the parent `.norg`
file relative to the root of the current workspace (e.g. `source/my-file`). This field is
a plain path string rather than a Norg link, since metadata values are plain strings.

Because `core.esupports.metagen` only writes metadata keys that exist in its `template`,
the module temporarily appends a `parent` entry to the template for the duration of the
file creation (passing the value through `create_file`'s `metadata` option) and removes it
again immediately afterwards, so user-configured templates are never modified.

`core.integrations.treesitter` must be loaded (it is a dependency of
`core.esupports.metagen`) for the `parent` subcommand to read the metadata.

## Example

```
:Neorg fork my idea notes
```

Given the current buffer is a `.norg` file located at `<workspace>/source/parent.norg`,
this creates `20240824233008.norg` (a `%Y%m%d%H%M%S` timestamp) in the current workspace (or workspace configured via
`workspace`) and injects:

```
@document.meta
title: My Idea Notes
parent: source/parent
...
@end
```

plus a `* My Idea Notes` heading at the top of the file.

To open the parent of the current note again:

```
:Neorg parent
```
