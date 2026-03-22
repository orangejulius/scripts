#!/usr/bin/env bash
# Save all tmux sessions, windows, panes, and scrollback history
# Usage: ./tmux-save-all.sh [output-dir]
# Restore: ./tmux-restore-all.sh [output-dir]

set -euo pipefail

SAVE_DIR="${1:-$HOME/tmux-save-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$SAVE_DIR"

echo "Saving tmux state to: $SAVE_DIR"

# Save session/window/pane structure
tmux list-sessions -F "#{session_name} #{session_created}" > "$SAVE_DIR/sessions.txt"

session_count=0
pane_count=0

while IFS= read -r session_name; do
  session_count=$((session_count + 1))
  session_dir="$SAVE_DIR/$(echo "$session_name" | tr '/' '-')"
  mkdir -p "$session_dir"

  # Save window list for this session
  tmux list-windows -t "$session_name" \
    -F "#{window_index} #{window_name} #{window_layout} #{window_active}" \
    > "$session_dir/windows.txt"

  while IFS=' ' read -r window_index window_name window_layout window_active; do
    window_dir="$session_dir/window-${window_index}"
    mkdir -p "$window_dir"

    # Save pane info for this window
    tmux list-panes -t "${session_name}:${window_index}" \
      -F "#{pane_index} #{pane_current_path} #{pane_current_command} #{pane_active} #{pane_width} #{pane_height}" \
      > "$window_dir/panes.txt"

    # Save window layout
    echo "$window_layout" > "$window_dir/layout.txt"
    echo "$window_name" > "$window_dir/name.txt"

    while IFS=' ' read -r pane_index pane_path pane_cmd pane_active pane_w pane_h; do
      pane_count=$((pane_count + 1))
      target="${session_name}:${window_index}.${pane_index}"
      outfile="$window_dir/pane-${pane_index}.txt"
      metafile="$window_dir/pane-${pane_index}.meta"

      # Save pane metadata
      cat > "$metafile" <<EOF
session=$session_name
window=$window_index
pane=$pane_index
path=$pane_path
command=$pane_cmd
active=$pane_active
width=$pane_w
height=$pane_h
EOF

      # Capture full scrollback (-S - means from the very beginning)
      if tmux capture-pane -t "$target" -p -S - > "$outfile" 2>/dev/null; then
        lines=$(wc -l < "$outfile")
        echo "  Saved $target ($pane_cmd in $pane_path): $lines lines"
      else
        echo "  WARN: Failed to capture $target"
      fi
    done < "$window_dir/panes.txt"

  done < <(tmux list-windows -t "$session_name" \
    -F "#{window_index} #{window_name} #{window_layout} #{window_active}")

done < <(tmux list-sessions -F "#{session_name}")

echo ""
echo "Done. Saved $session_count sessions, $pane_count panes to: $SAVE_DIR"
echo ""
echo "To search for Claude resume tokens:"
echo "  grep -r 'resume' '$SAVE_DIR' | grep -i 'claude\|token\|session'"
echo ""
echo "To restore session structure (no scrollback):"
echo "  $(dirname "$0")/tmux-restore-all.sh '$SAVE_DIR'"
