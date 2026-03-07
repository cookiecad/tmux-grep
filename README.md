# tmux-grep

Search across **all** tmux panes' scrollback history with fzf. Select a result to jump directly to that line in copy-mode with search highlighting.

![demo](https://github.com/user-attachments/assets/placeholder)

## Features

- Searches scrollback history across all panes, windows, and sessions
- fzf-powered fuzzy/exact search with live filtering
- Preview window shows context around each match
- Selecting a result switches to that pane, enters copy-mode at the exact line, and sets up the search pattern so `n`/`N` navigate between matches
- Runs in a tmux popup overlay (no extra panes created)

## Requirements

- tmux 3.2+ (for `display-popup`)
- [fzf](https://github.com/junegunn/fzf)

## Install with TPM

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'cookiecad/tmux-grep'
```

Then press `prefix + I` to install.

## Usage

Press `prefix + /` to open the search popup.

- Type to filter results (exact match by default)
- Preview pane shows surrounding context
- Press `Enter` to jump to the selected match
- Press `Escape` or `Ctrl-C` to cancel
- `Ctrl-S` toggles sort order

Once you jump to a match, you're in tmux copy-mode:
- `n` — next match
- `N` — previous match
- `q` — exit copy-mode

## Options

```tmux
# Change keybinding (default: /)
set -g @grep-key '/'

# Scrollback depth to search (default: -5000, use - for unlimited)
set -g @grep-depth '-5000'

# Context lines in preview (default: 5)
set -g @grep-context '5'
```

## License

MIT
