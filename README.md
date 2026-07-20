# sync-conflicts.nvim

Find and resolve [Syncthing](https://syncthing.net/) `sync-conflict` files
without leaving Neovim.

When Syncthing detects a conflicting edit, it leaves the original file in
place and drops a copy next to it, e.g.:

```
.obsidian/plugins/belki/data.json
.obsidian/plugins/belki/data.sync-conflict-20260716-170336-ZJ4LJPM.json
```

`sync-conflicts.nvim` scans your project for these files, lets you pick one
from a list, and opens a diff against the original so you can resolve it by
hand.

## Features

- 🔍 Recursively finds all `*.sync-conflict-*` files in the current
  working directory (uses `fd`/`rg` when available, falls back to `find`).
- 📋 Picker UI via [fzf-lua](https://github.com/ibhagwan/fzf-lua) if
  installed, otherwise falls back to `vim.ui.select`.
- 🔀 Opens a side-by-side diff (`original` | `conflict`) in a dedicated tab.
- ⌨️ Resolve directly from the diff: keep the conflict, keep the original,
  or just close and decide later.
- 🧹 No dependency on git — works on plain files anywhere in the tree.

## Requirements

- Neovim >= 0.9
- [`fd`](https://github.com/sharkdp/fd) or
  [`ripgrep`](https://github.com/BurntSushi/ripgrep) (optional, speeds up
  scanning; falls back to `find`)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) (optional, nicer picker;
  falls back to `vim.ui.select`)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  "maxi-di/sync-conflicts.nvim",
  config = true,
  cmd = "SyncConflicts",
}
```

With custom options:

```lua
return {
  "maxi-di/sync-conflicts.nvim",
  cmd = "SyncConflicts",
  opts = {
    keymaps = {
      keep_conflict = "<leader>sk",
      keep_original = "<leader>so",
      quit = "q",
    },
  },
}
```

## Usage

Run inside any project (typically the root of a Syncthing-synced folder):

```
:SyncConflicts
```

This lists every `sync-conflict` file found under the current working
directory. Selecting one opens a new tab with the original file on the
left and the conflict file on the right, both in diff mode.

### Diff-tab keymaps

| Key          | Action                                                                                                |
| ------------ | ----------------------------------------------------------------------------------------------------- |
| `<leader>sk` | Keep the **conflict** version — overwrites the original, deletes the conflict file, closes the tab    |
| `<leader>so` | Keep the **original** — deletes the conflict file, closes the tab                                     |
| `q`          | Turn off diff mode and close the tab, no files touched (only active while the window is in diff mode) |

## Configuration

Defaults:

```lua
require("sync-conflicts").setup({
  keymaps = {
    keep_conflict = "<leader>sk",
    keep_original = "<leader>so",
    quit = "q",
  },
})
```

## How it works

The plugin matches Syncthing's conflict-file naming convention:

```
<name>.sync-conflict-<YYYYMMDD>-<HHMMSS>-<ID>.<ext>
```

For each match it derives the original path (`<name>.<ext>` in the same
directory) and checks that it still exists before offering a diff.

## License

MIT
