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
    # Live link too, so /keybindings can still open it for editing.
    ".claude/keybindings.json".source = live "claude/keybindings.json";
    # Live link too, so /memory can still edit the instructions every session loads.
    ".claude/CLAUDE.md".source = live "claude/CLAUDE.md";
    ".claude/statusline.sh".source = ../../config/claude/statusline.sh;
  };

  # herdr: terminal multiplexer for coding agents (nixpkgs-unstable). Its
  # Claude hook script is written by `herdr integration install claude`,
  # a one-time step listed in the README.
  #
  # claude-session-diff: herdr prefix+d opens hunk (diff viewer, unstable) in
  # a split with the changes the focused pane's Claude session made. The
  # Claude hooks that track them are in config/claude/settings.json.
  #
  # bun: the official Discord Channels plugin (discord@claude-plugins-official)
  # is a Bun script. Its bot token and access list live in
  # ~/.claude/channels/discord/, outside this repo.
  home.packages = [
    pkgs.bun
    pkgs.herdr
    pkgs.hunk
    (pkgs.writeShellApplication {
      name = "claude-session-diff";
      runtimeInputs = with pkgs; [
        coreutils
        diffutils
        findutils
        git
        herdr
        hunk
        jq
      ];
      text = builtins.readFile ../../config/claude/session-diff.sh;
    })
  ];
  # Live link, because herdr rewrites its config itself.
  xdg.configFile."herdr/config.toml".source = live "herdr/config.toml";
}
