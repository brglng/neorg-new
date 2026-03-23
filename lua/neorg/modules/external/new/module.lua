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
                min_args = 0,
                name = "external.new",
            },
            ["new-template"] = {
                min_args = 1,
                name = "external.new-template",
            },
        })
    end)
end

module.config.public = {
    -- Which workspace to use for new files.
    -- If nil, uses the current workspace.
    workspace = nil,

    -- Callback function to generate the title from the subcommand arguments.
    ---@param args string[] All subcommand arguments passed to `:Neorg new` or `:Neorg new-template`
    ---@return string The title to inject into the metadata block of the new file
    ---               (if metadata injection is enabled via core.esupports.metagen)
    title = function(args)
        if #args == 0 then
            error("The default title generator requires at least one argument to generate a title. Please provide a title argument or configure a custom title generator.")
        end
        return table.concat(vim.tbl_map(function(arg)
            local first = vim.fn.nr2char(vim.fn.char2nr(arg:sub(1, vim.fn.strchars(arg, 1))))
            local rest = arg:sub(vim.fn.strlen(first) + 1)
            return vim.fn.toupper(first) .. rest
        end, args), " ")
    end,

    -- Callback function to generate the filename from the subcommand arguments.
    ---@param args string[] All subcommand arguments passed to `:Neorg new` or `:Neorg new-template`
    ---@return string The filename (including any subfolder path components) to create for the new file.
    filename = function(args)
        if #args == 0 then
            error("The default filename generator requires at least one argument to generate a filename. Please provide a title argument or configure a custom filename generator.")
        end
        return table.concat(vim.tbl_map(function(arg)
            return arg:lower()
        end, args), "-") .. ".norg"
    end,

    --- Callback function to generate the content from the subcommand arguments.
    ---@param name string? The name of the template, nil if the subcommand is `:Neorg new` rather than `:Neorg new-template`.
    ---@param args string[] All subcommand arguments passed to `:Neorg new` or `:Neorg new-template`
    ---@return string[] A list of lines to insert into the new file after the metadata block (if any)
    template = function(name, args)
        if #args == 0 then
            error("The default template generator requires at least one argument to generate content. Please provide a title argument or configure a custom template generator.")
        end
        local heading = table.concat(vim.tbl_map(function(arg)
            local first = vim.fn.nr2char(vim.fn.char2nr(arg:sub(1, vim.fn.strchars(arg, 1))))
            local rest = arg:sub(vim.fn.strlen(first) + 1)
            return vim.fn.toupper(first) .. rest
        end, args), " ")
        return { "* " .. heading }
    end,
}

---@class external.new
module.public = {
    --- Creates a new .norg file based on the supplied arguments.
    ---@param template_name string? The name of the template to use, or nil if the `:Neorg new` subcommand was used rather than `:Neorg new-template`.
    ---@param args string[] #Arguments passed to the `:Neorg new` or `:Neorg new-template` subcommand.
    new_file = function(template_name, args)
        local metagen = neorg.modules.loaded_modules["core.esupports.metagen"]
        local inject_metadata = metagen and (metagen.config.public.type == "auto" or metagen.config.public.type == "empty")

        local title_cb = module.config.public.title
        local filename_cb = module.config.public.filename
        local template_cb = module.config.public.template

        local title = title_cb(args)
        local filename = filename_cb(args)
        local workspace = module.config.public.workspace

        ---@type core.dirman.create_file_opts
        local opts = {}

        if inject_metadata then
            opts.metadata = { title = title }
        end

        module.required["core.dirman"].create_file(filename, workspace, opts)

        -- Capture the buffer of the newly created/opened file immediately after
        -- create_file() returns so that a late buffer switch does not cause the
        -- scheduled callback to operate on the wrong buffer.
        local target_buf = vim.api.nvim_get_current_buf()

        -- Add a top-level heading after the file has been opened (and metadata
        -- has been injected by core.esupports.metagen if applicable).
        if template_cb then
            vim.schedule(function()
                local content = template_cb(template_name, args)
                local buf = target_buf
                local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

                -- Determine the insertion point.
                -- When metadata is enabled, insert the content after the closing
                -- `@end` tag; otherwise insert at the very beginning of the file.
                local insert_at = 0
                if inject_metadata then
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
        module.public.new_file(nil, event.content)
    elseif event.split_type[2] == "external.new-template" then
        local template_name = event.content[1]
        local args = { unpack(event.content, 2) }
        module.public.new_file(template_name, args)
    end
end

module.events.subscribed = {
    ["core.neorgcmd"] = {
        ["external.new"] = true,
    },
}

return module
