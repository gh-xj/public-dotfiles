#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
nvim --headless --cmd "set rtp^=$repo_root/.config/nvim" -u "$repo_root/.config/nvim/init.lua" '+qa'
python3 "$repo_root/scripts/test-nvim-health.py"
nvim --headless -u NONE "+lua local c = dofile('$repo_root/.config/nvim/lua/plugins/ui.lua')[1]; vim.b.gitsigns_status_dict = {added=2,changed=3,removed=4}; local s=c.opts.sections.lualine_b[2].source(); assert(s.added==2 and s.modified==3 and s.removed==4)" '+qa'
