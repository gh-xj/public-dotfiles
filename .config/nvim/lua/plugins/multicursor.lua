return {
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    keys = {
      { "gl", mode = { "n", "v" }, desc = "Add cursor to next match of word" },
      { "gL", mode = { "n", "v" }, desc = "Add cursor to prev match of word" },
      { "g>", mode = { "n", "v" }, desc = "Skip to next match of word" },
      { "g<", mode = { "n", "v" }, desc = "Skip to prev match of word" },
      { "ga", mode = { "n", "v" }, desc = "Cursor on every match" },
    },
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()

      local set = vim.keymap.set

      -- Zed-aligned: match-based cursor adding
      set({ "n", "v" }, "gl", function() mc.matchAddCursor(1) end,
        { desc = "Add cursor to next match of word" })
      set({ "n", "v" }, "gL", function() mc.matchAddCursor(-1) end,
        { desc = "Add cursor to prev match of word" })
      set({ "n", "v" }, "g>", function() mc.matchSkipCursor(1) end,
        { desc = "Skip to next match of word" })
      set({ "n", "v" }, "g<", function() mc.matchSkipCursor(-1) end,
        { desc = "Skip to prev match of word" })
      set({ "n", "v" }, "ga", mc.matchAllAddCursors,
        { desc = "Cursor on every match (word under cursor in normal, selection in visual)" })

      -- Escape disables cursors or clears them (and falls back to :nohl).
      set("n", "<Esc>", function()
        if not mc.cursorsEnabled() then
          mc.enableCursors()
        elseif mc.hasCursors() then
          mc.clearCursors()
        else
          vim.cmd("nohl")
        end
      end)
    end,
  },
}
