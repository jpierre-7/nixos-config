{
  config,
  pkgs,
  repoDir,
  ...
}:
let
  live = path: config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/${path}";
in
{
  programs.claude-code = {
    enable = true; # claude-code from nixpkgs-unstable (overlays/default.nix)
    # Linked file by file, so ~/.claude and ~/.claude/skills stay real
    # directories: Claude Code keeps credentials and history in ~/.claude,
    # and skill installers write next to these.
    skills = ../../config/claude/skills;
  };

  home.file = {
    # Live link, because Claude Code rewrites settings.json itself (/config,
    # /model, plugin installs). Review `git diff` before committing.
    ".claude/settings.json".source = live "claude/settings.json";
    ".claude/statusline.sh".source = ../../config/claude/statusline.sh;
  };

  # herdr: terminal multiplexer for coding agents (nixpkgs-unstable). Its
  # Claude hook script is written by `herdr integration install claude`,
  # a one-time step listed in the README.
  home.packages = [ pkgs.herdr ];
  # Live link, because herdr rewrites its config itself.
  xdg.configFile."herdr/config.toml".source = live "herdr/config.toml";
}
