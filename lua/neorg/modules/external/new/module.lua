--[[
    file: New
    title: Create New Files
    description: The new module allows you to create new .norg files with a single command.
    summary: Easily create new .norg files in Neorg.
    ---
The new module exposes a `:Neorg new` command.

Provide one or more arguments to create a new `.norg` file. The arguments are forwarded
to the `title`, `filename` and `template` callback options to generate the respective
values for the new file.

Example:
```
:Neorg new my note title
```

This creates `my note title.norg` (or whatever `filename` returns) with the heading
`* my note title` (or whatever `template` returns).
--]]

local neorg = require("neorg.core")
local modules = neorg.modules

local module = modules.create("external.new")

module.setup = function()
    return {
        success = true,
        requires = {
            "core.dirman",
            "core.esupports.metagen",
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
    title = function(args)
        return table.concat(args, " ")
    end,

    -- Callback function to generate the filename from the subcommand arguments.
    -- Receives all subcommand arguments and must return the filename string.
    -- The filename may include subfolder path components; any missing directories
    -- will be created automatically.
    -- The default implementation joins all arguments with a single space.
    filename = function(args)
        return table.concat(args, " ")
    end,

    -- Callback function to generate the content from the subcommand
    -- arguments.  Receives all subcommand arguments and must return the content
    -- text string.  The default implementation generates a heading by joining
    -- all arguments with a single space.
    -- Set this option to nil to suppress content generation insertion entirely.
    template = function(args)
        local heading = table.concat(args, " ")
        return { "* " .. heading }
    end,
}

---@class external.new
module.public = {
    --- Creates a new .norg file based on the supplied arguments.
    ---@param ... string #Arguments passed to the `:Neorg new` command
    new_file = function(args)
        local title_cb = module.config.public.title
        local filename_cb = module.config.public.filename
        local template_cb = module.config.public.template

        local title = title_cb(args)
        local filename = filename_cb(args)
        local workspace = module.config.public.workspace

        ---@type core.dirman.create_file_opts
        local opts = {}

        opts.metadata = { title = title }

        module.required["core.dirman"].create_file(filename, workspace, opts)

        -- Capture the buffer of the newly created/opened file immediately after
        -- create_file() returns so that a late buffer switch does not cause the
        -- scheduled callback to operate on the wrong buffer.
        local target_buf = vim.api.nvim_get_current_buf()

        -- Add a top-level heading after the file has been opened (and metadata
        -- has been injected by core.esupports.metagen if applicable).
        if template_cb then
            vim.schedule(function()
                local metagen = neorg.modules.loaded_modules["core.esupports.metagen"]

                local content = template_cb(args)
                local buf = target_buf
                local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

                -- Determine the insertion point.
                -- When metadata is enabled, insert the content after the closing
                -- `@end` tag; otherwise insert at the very beginning of the file.
                local insert_at = 0
                if metagen.config.public.type == "auto" or metagen.config.public.type == "empty" then
                    for i, line in ipairs(lines) do
                        if line == "@end" then
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
                    -- Add a blank separator between the metadata block and the content.
                    table.insert(new_lines, "")
                end
                vim.list_extend(new_lines, content)

                vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, new_lines)
            end)
        end
    end,
}

module.on_event = function(event)
    if event.split_type[2] == "external.new" then
        module.public.new_file(event.content)
    end
end

module.events.subscribed = {
    ["core.neorgcmd"] = {
        ["external.new"] = true,
    },
}

return module
