# neorg-new

A Neorg plugin that adds a `:Neorg new` command for quickly creating new `.norg`
files with automatically generated metadata and content.

## Installation

Install the plugin with your preferred package manager and load it inside your
Neorg setup. The module requires both `core.dirman` and `core.esupports.metagen`
to be loaded as well.

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
:Neorg new <arg1> [arg2] ...
```

One or more arguments are required. By default the arguments are joined with a
single space to form the **title**, **filename**, and the **heading** placed at
the top of the new file.

**Example:**

```
:Neorg new my meeting notes
```

This creates `my meeting notes.norg` in the current (or configured) workspace,
injects a `@document.meta` block whose `title` field is set to
`my meeting notes`, and prepends the heading `* my meeting notes` after the
metadata block.

## Configuration

```lua
["external.new"] = {
    config = {
        -- Which workspace to use for new files.
        -- If nil, the current workspace is used.
        workspace = nil,

        -- Callback that receives the subcommand arguments as a table and
        -- returns the title string written into @document.meta.
        -- Default: join all arguments with a single space.
        title = function(args)
            return table.concat(args, " ")
        end,

        -- Callback that receives the subcommand arguments as a table and
        -- returns the file path (without the .norg extension).
        -- The path may contain subfolder components; any missing parent
        -- directories are created automatically.
        -- Default: join all arguments with a single space.
        filename = function(args)
            return table.concat(args, " ")
        end,

        -- Callback that receives the subcommand arguments as a table and
        -- returns a list of strings (lines) to insert into the new file.
        -- The lines are placed after the @document.meta block when
        -- core.esupports.metagen is configured to inject metadata
        -- (type = "auto" or "empty"), or at the very beginning of the file
        -- otherwise.
        -- Default: a single top-level heading formed by joining all arguments
        -- with a single space.
        -- Set to nil to insert no additional content.
        template = function(args)
            local heading = table.concat(args, " ")
            return { "* " .. heading }
        end,
    },
},
```

### Notes on metadata

Metadata is **always** injected into every new file created by `:Neorg new`,
with the `title` field set to the value returned by the `title` callback.
The actual injection is performed by `core.esupports.metagen`; make sure that
module is loaded and its `type` option is set to `"auto"` or `"empty"` for
metadata to appear in the file.

### Custom example

```lua
["external.new"] = {
    config = {
        workspace = "notes",
        -- kebab-case filename stored in a "pages" subfolder
        filename = function(args)
            return "pages/" .. table.concat(args, "-"):lower()
        end,
        -- custom template: heading + blank line + a TODO item
        template = function(args)
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
`pages/my-project-plan.norg` with the title `My Project Plan` in its metadata
and the following content after the metadata block:

```norg
* My Project Plan

- ( ) 
```
