# neorg-new

A Neorg plugin that adds a `:Neorg new` command for quickly creating new `.norg`
files with automatically generated content (and optional metadata).

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
:Neorg template <template_name> [arg1] [arg2] ...
```

For `:Neorg new`, one or more arguments are recommended (the default callbacks
require at least one). The arguments are forwarded to the `title`, `filename`,
and `template` callbacks to generate the respective values for the new file.

For `:Neorg template`, the first argument is the **template name** passed
as the first parameter to the `template` callback; the remaining arguments are
treated the same as with `:Neorg new`.

By default:

- The **title** is formed by capitalizing the first letter of each argument and
  joining them with a single space.
- The **filename** is formed by converting each argument to lowercase (with
  whitespace replaced by `-`) and joining them with `-`, with a `.norg`
  extension appended.
- The **heading** placed at the top of the file is the same as the title.

**Example:**

```
:Neorg new my meeting notes
```

This creates `my-meeting-notes.norg` in the current (or configured) workspace,
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
        title = function(args)
            return table.concat(vim.tbl_map(function(s)
                return vim.fn.toupper(vim.fn.strcharpart(s, 0, 1)) .. vim.fn.strcharpart(s, 1)
            end, args), " ")
        end,

        -- Callback that receives the subcommand arguments as a table and
        -- returns the file path (with the .norg extension).
        -- The path may contain subfolder components; any missing parent
        -- directories are created automatically.
        -- Default: convert each argument to lowercase (replacing whitespace
        -- with "-") and join with "-", then append ".norg"
        -- (e.g. {"my", "note"} -> "my-note.norg").
        filename = function(args)
            return table.concat(vim.tbl_map(function(arg)
                return vim.fn.substitute(vim.fn.tolower(arg), [[\s\+]], "-", "g")
            end, args), "-") .. ".norg"
        end,

        -- Callback that receives the template name (nil when using
        -- `:Neorg new`, or a string when using `:Neorg template`) and
        -- the subcommand arguments as a table, and returns a list of strings
        -- (lines) to insert into the new file.
        -- The lines are placed after the @document.meta block when
        -- core.esupports.metagen is configured to inject metadata
        -- (type = "auto" or "empty"), or at the very beginning of the file
        -- otherwise.
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

Metadata injection is **optional** and controlled by
`core.esupports.metagen`. When that module is loaded and its `type` option is
set to `"auto"` or `"empty"`, a `@document.meta` block is injected into each
new file with the `title` field set to the value returned by the `title`
callback. When `core.esupports.metagen` is not loaded, or its `type` is set to
`"none"`, no metadata block is generated and the `title` callback is not called.

### Custom example

```lua
["external.new"] = {
    config = {
        workspace = "notes",
        -- filename stored in a "pages" subfolder (override the default kebab-case)
        filename = function(args)
            return "pages/" .. table.concat(args, "-"):lower() .. ".norg"
        end,
        -- custom template: heading + blank line + a TODO item
        template = function(name, args)
            return {
                "* " .. table.concat(args, " "),
                "",
                "- ( ) ",
            }
        end,
    },
},
```

Running `:Neorg new My Project Plan` would create
`pages/my-project-plan.norg` (with the title `My Project Plan` in its metadata
if `core.esupports.metagen` is enabled) and the following content:

```norg
* My Project Plan

- ( ) 
```
