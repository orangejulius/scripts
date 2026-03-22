#!/usr/bin/env bash
# Restore tmux sessions from a save directory created by tmux-save-all.sh
# Usage: ./tmux-restore-all.sh <save-dir>
#
# What this restores:
#   - Session names
#   - Window names and layouts
#   - Pane working directories
#   - Scrollback history (by replaying content — can be slow for large histories)
#
# What it cannot restore:
#   - Running processes (you'll get a shell in each pane)
#   - Interactive program state (vim buffers, etc.)

set -euo pipefail

SAVE_DIR="${1:-}"
if [[ -z "$SAVE_DIR" || ! -d "$SAVE_DIR" ]]; then
  echo "Usage: $0 <save-dir>"
  echo "  save-dir: directory created by tmux-save-all.sh"
  exit 1
fi

RESTORE_SCROLLBACK="${RESTORE_SCROLLBACK:-1}"

echo "Restoring tmux state from: $SAVE_DIR"
echo "Scrollback restore: $RESTORE_SCROLLBACK (set RESTORE_SCROLLBACK=0 to skip)"
echo ""

restore_scrollback() {
  local target="$1"
  local history_file="$2"
  local lines
  lines=$(wc -l < "$history_file")

  if [[ $lines -eq 0 ]]; then
    return
  fi

  echo "  Restoring $lines lines of scrollback to $target..."

  # Pipe history into the pane. The content scrolls through the terminal,
  # landing in the scrollback buffer. Then clear to leave a clean prompt.
  # We use a temp script to avoid quoting issues with arbitrary content.
  local tmpscript
  tmpscript=$(mktemp /tmp/tmux-restore-XXXXXX.sh)
  cat > "$tmpscript" <<SCRIPT
cat $(printf '%q' "$history_file")
printf '\033[2J\033[H'  # clear screen (history stays in scrollback)
SCRIPT
  chmod +x "$tmpscript"
  tmux send-keys -t "$target" "bash $tmpscript; rm -f $tmpscript" Enter
  # Wait briefly so the content loads before moving to next pane
  sleep 0.3
}

while IFS= read -r session_name; do
  session_dir="$SAVE_DIR/$(echo "$session_name" | tr '/' '-')"
  [[ -d "$session_dir" ]] || continue

  # Create session (detached), or skip if it already exists
  if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "Session '$session_name' already exists, skipping creation."
    continue
  fi

  echo "Creating session: $session_name"
  tmux new-session -d -s "$session_name" 2>/dev/null || true

  first_window=1
  while IFS=' ' read -r window_index window_name window_layout window_active; do
    window_dir="$session_dir/window-${window_index}"
    [[ -d "$window_dir" ]] || continue

    if [[ $first_window -eq 1 ]]; then
      # Rename the auto-created first window
      tmux rename-window -t "${session_name}:1" "$window_name" 2>/dev/null || true
      target_window="${session_name}:1"
      first_window=0
    else
      tmux new-window -t "$session_name" -n "$window_name"
      target_window="${session_name}:${window_index}"
    fi

    # Restore panes
    first_pane=1
    while IFS=' ' read -r pane_index pane_path pane_cmd pane_active pane_w pane_h; do
      if [[ $first_pane -eq 1 ]]; then
        target="${target_window}.1"
        # cd to the saved working directory
        tmux send-keys -t "$target" "cd $(printf '%q' "$pane_path")" Enter
        first_pane=0
      else
        # Split to create additional panes
        tmux split-window -t "$target_window" -c "$pane_path" 2>/dev/null || \
          tmux split-window -t "$target_window"
        target="${target_window}.${pane_index}"
      fi

      # Restore scrollback if enabled and file exists
      if [[ "$RESTORE_SCROLLBACK" == "1" ]]; then
        history_file="$window_dir/pane-${pane_index}.txt"
        if [[ -f "$history_file" ]]; then
          restore_scrollback "$target" "$history_file"
        fi
      fi

    done < "$window_dir/panes.txt"

    # Re-apply the saved layout (best effort)
    if [[ -f "$window_dir/layout.txt" ]]; then
      layout=$(cat "$window_dir/layout.txt")
      tmux select-layout -t "$target_window" "$layout" 2>/dev/null || true
    fi

  done < "$session_dir/windows.txt"

done < <(ls "$SAVE_DIR" | grep -v '^\.' | sed 's|.*/||')

echo ""
echo "Restore complete. Attach with: tmux attach -t <session-name>"
echo "List sessions: tmux ls"
