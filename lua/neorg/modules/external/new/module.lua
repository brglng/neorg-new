--[[
    file: New
    title: Create New Files
    description: The new module allows you to create new .norg files with a single command.
    summary: Easily create new .norg files in Neorg.
    ---
The new module exposes the `:Neorg new`, `:Neorg new-from-template`, `:Neorg fork`,
`:Neorg fork-from-template` and `:Neorg parent` commands.

Provide one or more arguments to create a new `.norg` file. The arguments are forwarded
to the `title`, `filename` and `template` callback options to generate the respective
values for the new file.

Example:
```
:Neorg new my note title
```

This creates `my note title.norg` (or whatever `filename` returns) with the heading
`* my note title` (or whatever `template` returns).

The `fork` subcommand behaves exactly like `new`, except it is only available when the
current buffer is a `.norg` file (which is then treated as the parent of the forked note).
A forked file has an extra `parent` field in its metadata holding the path of that parent
file, resolved relative to the root of the current workspace. Forking requires metadata
injection (`core.esupports.metagen` with `type = "auto"` or `"empty"`); if it is disabled,
`:Neorg fork` fails with an error.

The `parent` subcommand opens the parent of the current `.norg` file, as recorded in its
`parent` metadata field. It is only available inside a `.norg` file and fails with an error
if the current file carries no `parent` field.
--]]

local neorg = require("neorg.core")
local modules = neorg.modules
local Path = require("pathlib")

local module = modules.create("external.new")

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
                min_args = 0,
                name = "external.new",
            },
            ["new-from-template"] = {
                min_args = 1,
                name = "external.new-from-template",
            },
            fork = {
                min_args = 0,
                condition = "norg",
                name = "external.fork",
            },
            ["fork-from-template"] = {
                min_args = 1,
                condition = "norg",
                name = "external.fork-from-template",
            },
            parent = {
                min_args = 0,
                condition = "norg",
                name = "external.parent",
            },
        })
    end)
end

module.config.public = {
    -- Which workspace to use for new files.
    -- If nil, uses the current workspace.
    workspace = nil,

    -- Callback function to generate the title from the subcommand arguments.
    ---@param args string[] All subcommand arguments passed to `:Neorg new`, `:Neorg new-from-template`, `:Neorg fork` or `:Neorg fork-from-template`
    ---@return string The title to inject into the metadata block of the new file
    ---               (if metadata injection is enabled via core.esupports.metagen)
    title = function(args)
        if #args == 0 then
            return ""
        end
        return table.concat(vim.tbl_map(function(s)
            return vim.fn.toupper(vim.fn.strcharpart(s, 0, 1)) .. vim.fn.strcharpart(s, 1)
        end, args), " ")
    end,

    -- Callback function to generate the filename from the subcommand arguments.
    ---@param args string[] All subcommand arguments passed to `:Neorg new`, `:Neorg new-from-template`, `:Neorg fork` or `:Neorg fork-from-template`
    ---@return string The filename (including any subfolder path components) to create for the new file.
    filename = function(args)
        return os.date("%Y%m%d%H%M%S")
    end,

    --- Callback function to generate the content from the subcommand arguments.
    ---@param name string? The name of the template, nil if the subcommand is `:Neorg new` or `:Neorg fork` rather than `:Neorg new-from-template` or `:Neorg fork-from-template`.
    ---@param args string[] All subcommand arguments passed to `:Neorg new`, `:Neorg new-from-template`, `:Neorg fork` or `:Neorg fork-from-template`
    ---@return string[] A list of lines to insert into the new file after the metadata block (if any)
    template = function(name, args)
        if #args == 0 then
            return {}
        end
        local heading = table.concat(vim.tbl_map(function(s)
            return vim.fn.toupper(vim.fn.strcharpart(s, 0, 1)) .. vim.fn.strcharpart(s, 1)
        end, args), " ")
        return { "* " .. heading }
    end,
}

module.private = {
    --- Creates and opens a new `.norg` file based on the supplied arguments. This is the
    --- shared implementation for both the `new` and `fork` subcommands.
    ---@param template_name string? The name of the template to use, or nil for the plain `:Neorg new`/`:Neorg fork` subcommands.
    ---@param args string[] #Arguments forwarded to the `title`, `filename` and `template` callbacks.
    ---@param parent_path string? When non-nil and metadata injection is enabled, a
    ---                       `parent` field holding this path (relative to the current
    ---                       workspace) is injected into the new file's metadata.
    create_new_file = function(template_name, args, parent_path)
        local metagen = neorg.modules.loaded_modules["core.esupports.metagen"]
        local inject_metadata =
            metagen and (metagen.config.public.type == "auto" or metagen.config.public.type == "empty")

        local title_cb = module.config.public.title
        local filename_cb = module.config.public.filename
        local template_cb = module.config.public.template

        local title = title_cb(args)
        local filename = filename_cb(args) .. ".norg"
        local workspace = module.config.public.workspace

        ---@type core.dirman.create_file_opts
        local opts = {}

        if inject_metadata then
            opts.metadata = { title = title }
        end

        -- `core.esupports.metagen` only writes metadata keys that exist in its `template`,
        -- so a `parent` entry must be temporarily appended before the metadata is generated.
        -- Because `core.dirman.create_file` broadcasts the `file_created` event synchronously,
        -- metagen injects the metadata (including the `parent` field) during that call, which
        -- means the temporary template entry can be removed again immediately afterwards.
        local template_appended = false
        if parent_path and inject_metadata then
            opts.metadata.parent = parent_path

            local parent_key_present = false
            for _, entry in ipairs(metagen.config.public.template) do
                if entry[1] == "parent" then
                    parent_key_present = true
                    break
                end
            end

            if not parent_key_present then
                table.insert(metagen.config.public.template, { "parent" })
                template_appended = true
            end
        end

        module.required["core.dirman"].create_file(filename, workspace, opts)

        if template_appended then
            table.remove(metagen.config.public.template)
        end

        -- Capture the buffer of the newly created/opened file immediately after
        -- create_file() returns so that a late buffer switch does not cause the
        -- scheduled callback to operate on the wrong buffer.
        local target_buf = vim.api.nvim_get_current_buf()

        if template_cb then
            vim.schedule(function()
                -- Add a top-level heading after the file has been opened (and metadata
                -- has been injected by core.esupports.metagen if applicable).
                local content = template_cb(template_name, args)
                if content and #content > 0 then
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
                end
            end)
        end
    end,

    --- Builds the string to store in a forked file's `parent` metadata field: the path of
    --- the given parent buffer, relative to the root of the current workspace (e.g.
    --- `subdir/my-note` for a file at `<workspace>/subdir/my-note.norg`). A plain path
    --- string is used rather than a Norg link because metadata values are plain strings.
    ---@param buf number #The buffer of the parent norg file
    ---@return string #The parent's path relative to the root of the current workspace
    get_parent_file_path = function(buf)
        local dirman = module.required["core.dirman"]
        -- `get_current_workspace()` returns a single `{ name, path }` pair table (not
        -- multiple return values), so index it instead of unpacking.
        local current_workspace = dirman.get_current_workspace()
        local ws_name, ws_root = current_workspace[1], current_workspace[2]

        local ws_root_str = tostring(ws_root)
        if ws_root_str:sub(-1) ~= "/" and ws_root_str:sub(-1) ~= "\\" then
            ws_root_str = ws_root_str .. "/"
        end

        local parent_path = vim.api.nvim_buf_get_name(buf)
        if parent_path:sub(1, ws_root_str:len()) ~= ws_root_str then
            error(
                ("The current `.norg` file is not located inside the current workspace `%s`, so a workspace-relative `parent` path cannot be generated."):format(
                    tostring(ws_name)
                )
            )
        end

        local parent_rel = parent_path:sub(ws_root_str:len() + 1)
        parent_rel = parent_rel:gsub("%.norg$", "")

        return parent_rel
    end,
}

---@class external.new
module.public = {
    --- Creates a new .norg file based on the supplied arguments.
    ---@param template_name string? The name of the template to use, or nil if the `:Neorg new` subcommand was used rather than `:Neorg new-from-template`.
    ---@param args string[] #Arguments passed to the `:Neorg new` or `:Neorg new-from-template` subcommand.
    new_file = function(template_name, args)
        module.private.create_new_file(template_name, args)
    end,

    --- Creates a forked .norg file based on the supplied arguments. The current buffer
    --- is the parent of the fork and is recorded in the new file's metadata via a
    --- `parent` field (a path to the parent file relative to the current workspace).
    ---@param template_name string? The name of the template to use, or nil if the `:Neorg fork` subcommand was used rather than `:Neorg fork-from-template`.
    ---@param args string[] #Arguments passed to the `:Neorg fork` or `:Neorg fork-from-template` subcommand.
    ---@param parent_buf number? #The buffer of the parent norg file; defaults to the current buffer.
    fork_file = function(template_name, args, parent_buf)
        parent_buf = parent_buf or vim.api.nvim_get_current_buf()

        local filetype = vim.bo[parent_buf].filetype
        if filetype ~= "norg" then
            error("The `:Neorg fork` command can only be executed from a `.norg` file. The current buffer is used as the parent of the forked note.")
        end

        local metagen = neorg.modules.loaded_modules["core.esupports.metagen"]
        local inject_metadata =
            metagen and (metagen.config.public.type == "auto" or metagen.config.public.type == "empty")
        if not inject_metadata then
            error("The `:Neorg fork` command requires metadata injection to record the `parent` field. Load `core.esupports.metagen` with `type = \"auto\"` or `type = \"empty\"`.")
        end

        local parent_path = module.private.get_parent_file_path(parent_buf)
        module.private.create_new_file(template_name, args, parent_path)
    end,

    --- Opens the parent of the current .norg file, as recorded in its `parent` metadata
    --- field. The field stores the parent's path relative to the current workspace root.
    ---@param parent_buf number? #The buffer of the file whose parent should be opened; defaults to the current buffer.
    open_parent = function(parent_buf)
        parent_buf = parent_buf or vim.api.nvim_get_current_buf()

        local ts_module = modules.get_module("core.integrations.treesitter")
        if not ts_module then
            error("The `:Neorg parent` command requires `core.integrations.treesitter` to be loaded in order to read the `parent` metadata field.")
        end

        local metadata = ts_module.get_document_metadata(parent_buf) or {}
        local parent_path = metadata.parent
        if not parent_path or parent_path == vim.NIL then
            error("The current file has no `parent` field in its metadata, so there is no parent to open.")
        end

        local dirman = module.required["core.dirman"]
        local current_workspace = dirman.get_current_workspace()
        local ws_root = current_workspace[2]

        local target = (Path(ws_root) / tostring(parent_path)):add_suffix(".norg")
        vim.cmd("e " .. target:cmd_string())
    end,
}

module.on_event = function(event)
    if event.split_type[2] == "external.new" then
        local args = { unpack(event.content, 1, #event.content) }
        module.public.new_file(nil, args)
    elseif event.split_type[2] == "external.new-from-template" then
        local template_name = event.content[1]
        local args = { unpack(event.content, 2, #event.content) }
        module.public.new_file(template_name, args)
    elseif event.split_type[2] == "external.fork" then
        local args = { unpack(event.content, 1, #event.content) }
        module.public.fork_file(nil, args, event.buffer)
    elseif event.split_type[2] == "external.fork-from-template" then
        local template_name = event.content[1]
        local args = { unpack(event.content, 2, #event.content) }
        module.public.fork_file(template_name, args, event.buffer)
    elseif event.split_type[2] == "external.parent" then
        module.public.open_parent(event.buffer)
    end
end

module.events.subscribed = {
    ["core.neorgcmd"] = {
        ["external.new"] = true,
        ["external.new-from-template"] = true,
        ["external.fork"] = true,
        ["external.fork-from-template"] = true,
        ["external.parent"] = true,
    },
}

return module
