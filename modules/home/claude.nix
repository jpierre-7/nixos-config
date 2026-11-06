{
  config,
  lib,
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
    # Live link, so /keybindings can still open it for editing.
    ".claude/keybindings.json".source = live "claude/keybindings.json";
    # Live link too, so /memory can still edit the instructions every session loads.
    ".claude/CLAUDE.md".source = live "claude/CLAUDE.md";
    ".claude/statusline.sh".source = ../../config/claude/statusline.sh;
    # A mod (a plugin with hooks), which Claude Code auto-loads from ~/.claude/skills.
    # One link for the whole folder, unlike the skills above: linked file by
    # file, its module resolves outside the folder and Claude Code refuses it
    # as a path traversal, saying so only in the debug log.
    ".claude/skills/prompt-cache-control".source = ../../config/claude/mods/prompt-cache-control;
  };

  # Claude Code rewrites settings.json itself (/config, /model, plugin installs).
  # Review `git diff` before committing. Linked here instead of through
  # home.file: Claude Code puts its temp file next to the symlink's target, and
  # a home.file link targets the read-only store, so the write fails with EROFS.
  home.activation.linkClaudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ln -sfn $VERBOSE_ARG ${repoDir}/config/claude/settings.json ${config.home.homeDirectory}/.claude/settings.json
  '';

  # /pstack:setup-pstack rewrites its model rule with Claude Code's Write tool,
  # so it gets the same direct link as settings.json above. Claude Code loads
  # every .md file in ~/.claude/rules into each new session.
  home.activation.linkClaudePstackModels = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run mkdir -p $VERBOSE_ARG ${config.home.homeDirectory}/.claude/rules
    run ln -sfn $VERBOSE_ARG ${repoDir}/config/claude/rules/pstack-models.md ${config.home.homeDirectory}/.claude/rules/pstack-models.md
  '';

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
  #
  # terminal-browser: the terminal-browser@terminal-browser plugin runs it from
  # PATH to open a browser inside Claude Code (/browser).
  home.packages = [
    pkgs.bun
    pkgs.herdr
    pkgs.hunk
    (pkgs.callPackage ../../pkgs/terminal-browser.nix { })
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
