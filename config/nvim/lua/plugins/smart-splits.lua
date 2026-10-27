return {
  "mrjones2014/smart-splits.nvim",
  lazy = false, -- must load at startup so it can set IS_NVIM for WezTerm
  keys = {
    { "<C-h>",   function() require("smart-splits").move_cursor_left() end,  desc = "Move left" },
    { "<C-j>",   function() require("smart-splits").move_cursor_down() end,  desc = "Move down" },
    { "<C-k>",   function() require("smart-splits").move_cursor_up() end,    desc = "Move up" },
    { "<C-l>",   function() require("smart-splits").move_cursor_right() end, desc = "Move right" },
    { "<C-A-h>", function() require("smart-splits").resize_left() end,       desc = "Resize left" },
    { "<C-A-j>", function() require("smart-splits").resize_down() end,       desc = "Resize down" },
    { "<C-A-k>", function() require("smart-splits").resize_up() end,         desc = "Resize up" },
    { "<C-A-l>", function() require("smart-splits").resize_right() end,      desc = "Resize right" },
  },
}
