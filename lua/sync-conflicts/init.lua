-- sync-conflicts.lua
--
-- Поиск файлов-конфликтов Syncthing (*.sync-conflict-YYYYMMDD-HHMMSS-XXXXXXX.ext)
-- в текущем проекте и разрешение их через diff с оригиналом.
--
-- Структура плагина (local-plugins/sync-conflicts.nvim):
--   local-plugins/sync-conflicts.nvim/lua/sync-conflicts.lua   <- этот файл
--
-- lazy.nvim spec:
--   return {
--     dir = vim.fn.stdpath("config") .. "/local-plugins/sync-conflicts.nvim",
--     name = "sync-conflicts",
--     config = true,       -- вызовет require("sync-conflicts").setup({})
--     cmd = "SyncConflicts",
--   }
--
-- Требует (опционально, но желательно): fd (или rg), fzf-lua.

local M = {}

local defaults = {
    -- маппинги в diff-табе
    keymaps = {
        keep_conflict = "<leader>sk", -- оставить версию конфликта
        keep_original = "<leader>so", -- оставить оригинал
        quit = "q",               -- закрыть diff, ничего не меняя
    },
}

local opts = vim.deepcopy(defaults)

-- ─────────────────────────────────────────────────────────────
-- Поиск конфликтных файлов
-- ─────────────────────────────────────────────────────────────

-- data.sync-conflict-20260716-170336-ZJ4LJPM.json
--     ^base                ^date    ^time  ^id  ^ext
local CONFLICT_PATTERN =
"^(.+)%.sync%-conflict%-(%d%d%d%d%d%d%d%d)%-(%d%d%d%d%d%d)%-(%w+)(%.[%w]+)$"

local function project_root()
    return vim.fn.getcwd()
end

-- Быстрый поиск файлов, содержащих "sync-conflict" в имени
local function raw_scan(root)
    if vim.fn.executable("fd") == 1 then
        return vim.fn.systemlist({
            "fd", "--type", "f", "--hidden", "--no-ignore-vcs",
            "-E", ".git",
            "sync-conflict",
            root,
        })
    elseif vim.fn.executable("rg") == 1 then
        local files = vim.fn.systemlist({
            "rg", "--files", "--hidden", "--glob", "!.git", root,
        })
        local filtered = {}
        for _, f in ipairs(files) do
            if f:find("sync-conflict", 1, true) then
                table.insert(filtered, f)
            end
        end
        return filtered
    else
        return vim.fn.systemlist({
            "find", root, "-type", "f", "-name", "*sync-conflict*",
        })
    end
end

--- Возвращает список конфликтов:
--- { conflict_path, original_path, date, time, id, original_exists }
function M.find_conflicts()
    local root = project_root()
    local files = raw_scan(root)
    local conflicts = {}

    for _, path in ipairs(files) do
        local dir = vim.fn.fnamemodify(path, ":h")
        local name = vim.fn.fnamemodify(path, ":t")
        local base, date, time, id, ext = name:match(CONFLICT_PATTERN)
        if base then
            local original = dir .. "/" .. base .. ext
            table.insert(conflicts, {
                conflict_path = path,
                original_path = original,
                date = date,
                time = time,
                id = id,
                original_exists = vim.fn.filereadable(original) == 1,
            })
        end
    end

    table.sort(conflicts, function(a, b)
        return a.conflict_path < b.conflict_path
    end)

    return conflicts
end

-- ─────────────────────────────────────────────────────────────
-- Diff-вью и разрешение конфликта
-- ─────────────────────────────────────────────────────────────

local function set_resolve_keymaps(bufnr, entry)
    local kopts = {buffer = bufnr, silent = true, nowait = true}

    vim.keymap.set("n", opts.keymaps.keep_conflict, function()
        M.keep_conflict(entry)
    end, vim.tbl_extend("force", kopts, {desc = "Sync-conflict: оставить версию конфликта"}))

    vim.keymap.set("n", opts.keymaps.keep_original, function()
        M.keep_original(entry)
    end, vim.tbl_extend("force", kopts, {desc = "Sync-conflict: оставить оригинал"}))

    vim.keymap.set("n", opts.keymaps.quit, function()
        if not vim.wo.diff then
            return
        end
        vim.cmd("diffoff!")
        vim.cmd("tabclose")
    end, vim.tbl_extend("force", kopts, {desc = "Sync-conflict: закрыть diff"}))
end

--- Открывает вертикальный diff: оригинал | конфликт, в отдельном табе
function M.open_diff(entry)
    if not entry.original_exists then
        vim.notify(
            "Оригинальный файл не найден: " .. entry.original_path,
            vim.log.levels.WARN
        )
        return
    end

    vim.cmd("tabnew " .. vim.fn.fnameescape(entry.original_path))
    vim.cmd("diffthis")
    local orig_buf = vim.api.nvim_get_current_buf()

    vim.cmd("vsplit " .. vim.fn.fnameescape(entry.conflict_path))
    vim.cmd("diffthis")
    local conf_buf = vim.api.nvim_get_current_buf()

    set_resolve_keymaps(orig_buf, entry)
    set_resolve_keymaps(conf_buf, entry)

    vim.notify(
        string.format(
            "%s — оставить конфликт, %s — оставить оригинал, %s — выйти",
            opts.keymaps.keep_conflict, opts.keymaps.keep_original, opts.keymaps.quit
        ),
        vim.log.levels.INFO
    )
end

--- Заменить оригинал содержимым конфликта и удалить conflict-файл
function M.keep_conflict(entry)
    local lines = vim.fn.readfile(entry.conflict_path)
    vim.fn.writefile(lines, entry.original_path)
    vim.fn.delete(entry.conflict_path)
    vim.notify("Оригинал обновлён из конфликта, файл конфликта удалён: " .. entry.conflict_path)
    vim.cmd("diffoff!")
    vim.cmd("tabclose")
end

--- Оставить оригинал как есть, просто удалить conflict-файл
function M.keep_original(entry)
    vim.fn.delete(entry.conflict_path)
    vim.notify("Оригинал сохранён, файл конфликта удалён: " .. entry.conflict_path)
    vim.cmd("diffoff!")
    vim.cmd("tabclose")
end

-- ─────────────────────────────────────────────────────────────
-- UI: список конфликтов
-- ─────────────────────────────────────────────────────────────

local function format_entry(e)
    local rel = vim.fn.fnamemodify(e.conflict_path, ":.")
    local marker = e.original_exists and "" or "  [нет оригинала]"
    return string.format(
        "%s  (%s %s:%s:%s)%s",
        rel, e.date, e.time:sub(1, 2), e.time:sub(3, 4), e.time:sub(5, 6), marker
    )
end

function M.pick()
    local conflicts = M.find_conflicts()

    if #conflicts == 0 then
        vim.notify("Файлы sync-conflict не найдены", vim.log.levels.INFO)
        return
    end

    local labels, by_label = {}, {}
    for _, e in ipairs(conflicts) do
        local label = format_entry(e)
        table.insert(labels, label)
        by_label[label] = e
    end

    local ok_fzf, fzf = pcall(require, "fzf-lua")
    if ok_fzf then
        fzf.fzf_exec(labels, {
            prompt = "Sync conflicts> ",
            actions = {
                ["default"] = function(selected)
                    local e = by_label[selected[1]]
                    if e then M.open_diff(e) end
                end,
            },
        })
    else
        vim.ui.select(labels, {prompt = "Sync conflicts:"}, function(choice)
            if not choice then return end
            local e = by_label[choice]
            if e then M.open_diff(e) end
        end)
    end
end

-- ─────────────────────────────────────────────────────────────
-- setup()
-- ─────────────────────────────────────────────────────────────

local did_setup = false

function M.setup(user_opts)
    opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})

    if did_setup then
        return
    end
    did_setup = true

    vim.api.nvim_create_user_command("SyncConflicts", function()
        M.pick()
    end, {desc = "Показать и разрешить Syncthing sync-conflict файлы в проекте"})
end

return M
