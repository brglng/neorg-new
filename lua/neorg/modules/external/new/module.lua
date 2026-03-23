--[[
    file: New
    title: Create New Files
    description: The new module allows you to create new .norg files with a single command.
    summary: Easily create new .norg files in Neorg.
    ---
The new module exposes a `:Neorg new` command.

Provide one or more arguments to create a new `.norg` file. The arguments are forwarded
to the `title`, `filename` and `heading` callback options to generate the respective
values for the new file.

Example:
```
:Neorg new my note title
```

This creates `my note title.norg` (or whatever `filename` returns) with the heading
`* my note title` (or whatever `heading` returns).
--]]

local neorg = require("neorg.core")
local modules = neorg.modules

local module = modules.create("external.new")

local METADATA_END_TAG = "@end"

module.setup = function()
    return {
        success = true,
        requires = {
            "core.dirman",
        },
    }
end

module.load = function()
    modules.await("core.neorgcmd", function(neorgcmd)
        neorgcmd.add_commands_from_table({
            new = {
                min_args = 1,
                name = "external.new",
            },
        })
    end)
end

module.config.public = {
    -- Which workspace to use for new files.
    -- If nil, uses the current workspace.
    workspace = nil,

    -- Callback function to generate the title from the subcommand arguments.
    -- Receives all subcommand arguments and must return the formatted title string.
    -- The default implementation joins all arguments with a single space.
    title = function(...)
        return table.concat({ ... }, " ")
    end,

    -- Callback function to generate the filename from the subcommand arguments.
    -- Receives all subcommand arguments and must return the filename string.
    -- The filename may include subfolder path components; any missing directories
    -- will be created automatically.
    -- The default implementation joins all arguments with a single space.
    filename = function(...)
        return table.concat({ ... }, " ")
    end,

    -- Whether to inject document metadata at the top of the new file.
    -- When true the `core.esupports.metagen` module is used to inject metadata,
    -- and the `title` field in the metadata is set to the formatted title.
    metadata = false,

    -- Callback function to generate the top-level heading from the subcommand
    -- arguments.  Receives all subcommand arguments and must return the heading
    -- text string.  The default implementation joins all arguments with a single
    -- space.
    -- Set this option to nil to suppress heading insertion entirely.
    heading = function(...)
        return table.concat({ ... }, " ")
    end,
}

---@class external.new
module.public = {
    version = "0.0.1",

    --- Creates a new .norg file based on the supplied arguments.
    ---@param ... string #Arguments passed to the `:Neorg new` command
    new_file = function(...)
        local args = { ... }

        local title_cb = module.config.public.title
        local filename_cb = module.config.public.filename
        local heading_cb = module.config.public.heading

        local title = title_cb(unpack(args))
        local filename = filename_cb(unpack(args))
        local workspace = module.config.public.workspace

        ---@type core.dirman.create_file_opts
        local opts = {}

        if module.config.public.metadata then
            opts.metadata = { title = title }
        end

        module.required["core.dirman"].create_file(filename, workspace, opts)

        -- Capture the buffer of the newly created/opened file immediately after
        -- create_file() returns so that a late buffer switch does not cause the
        -- scheduled callback to operate on the wrong buffer.
        local target_buf = vim.api.nvim_get_current_buf()

        -- Add a top-level heading after the file has been opened (and metadata
        -- has been injected by core.esupports.metagen if applicable).
        if heading_cb then
            vim.schedule(function()
                local heading_text = heading_cb(unpack(args))
                local buf = target_buf
                local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

                -- Determine the insertion point.
                -- When metadata is enabled, insert the heading after the closing
                -- `@end` tag; otherwise insert at the very beginning of the file.
                local insert_at = 0
                if module.config.public.metadata then
                    for i, line in ipairs(lines) do
                        if line == METADATA_END_TAG then
                            -- `i` is the 1-based Lua index of the `@end` line.
                            -- nvim_buf_set_lines uses 0-based indices, so passing
                            -- `i` as both start and end inserts *after* `@end`.
                            insert_at = i
                            break
                        end
                    end
                end

                -- Build the lines to insert.
                local new_lines = {}
                if insert_at > 0 then
                    -- Add a blank separator between the metadata block and the heading.
                    table.insert(new_lines, "")
                end
                table.insert(new_lines, "* " .. heading_text)

                vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, new_lines)
                vim.cmd("w")
            end)
        end
    end,
}

module.on_event = function(event)
    if event.split_type[2] == "external.new" then
        module.public.new_file(unpack(event.content))
    end
end

module.events.subscribed = {
    ["core.neorgcmd"] = {
        ["external.new"] = true,
    },
}

return module
