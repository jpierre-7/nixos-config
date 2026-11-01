# Noctalia template (modules/home/noctalia.nix). Noctalia renders it to
# ~/.cache/noctalia/claude-statusline-colors.sh in its current palette, and
# statusline.sh sources that, so a palette change shows on the next update.
C_PRIMARY=$'\033[38;2;{{colors.primary.default.red}};{{colors.primary.default.green}};{{colors.primary.default.blue}}m'
C_SECONDARY=$'\033[38;2;{{colors.secondary.default.red}};{{colors.secondary.default.green}};{{colors.secondary.default.blue}}m'
C_TERTIARY=$'\033[38;2;{{colors.tertiary.default.red}};{{colors.tertiary.default.green}};{{colors.tertiary.default.blue}}m'
C_ERROR=$'\033[38;2;{{colors.error.default.red}};{{colors.error.default.green}};{{colors.error.default.blue}}m'
C_MUTED=$'\033[38;2;{{colors.on_surface_variant.default.red}};{{colors.on_surface_variant.default.green}};{{colors.on_surface_variant.default.blue}}m'
