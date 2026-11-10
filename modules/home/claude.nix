{
  config,
  inputs,
  lib,
  pkgs,
  repoDir,
  ...
}:
let
  live = path: config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/${path}";
  terminalBrowser = pkgs.callPackage ../../pkgs/terminal-browser.nix { };
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
    # Thumbnails of pasted images above the prompt; claude-paste-preview below
    # reads them from the clipboard.
    ".claude/skills/pasted-image-preview".source = ../../config/claude/mods/pasted-image-preview;
    # Left to itself, terminal-browser links its skill into ~/.claude/skills and
    # ~/.agents/skills on first run, to one store path that a later update or GC
    # leaves dangling. "no" here is its own opt-out for that, and it's what its
    # setup would save. force replaces the link it already made on this machine.
    ".claude/skills/terminal-browser" = {
      source = "${terminalBrowser}/lib/terminal-browser/skills/default/terminal-browser";
      force = true;
    };
    ".local/state/terminal-browser/skills-choice".text = "no\n";
    # Pinned by the mattpocock-skills flake input. Don't run this skill: it
    # would add a second, weaker copy of the hook. The real one is
    # block-dangerous-git below, called from config/claude/settings.json.
    ".claude/skills/git-guardrails-claude-code".source =
      "${inputs.mattpocock-skills}/skills/misc/git-guardrails-claude-code";
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
  #
  # block-dangerous-git: the Claude hook that asks before a git push and blocks
  # destructive git commands. Its jq and shfmt (which parses each command, so
  # quoted text doesn't count) are pinned here, so they can't go missing.
  #
  # claude-paste-preview: the pasted-image-preview mod runs it from PATH to
  # thumbnail the clipboard image a Ctrl+V just attached.
  home.packages = [
    pkgs.bun
    pkgs.herdr
    pkgs.hunk
    terminalBrowser
    (pkgs.writeShellApplication {
      name = "block-dangerous-git";
      runtimeInputs = with pkgs; [
        gnugrep
        jq
        shfmt
      ];
      text = builtins.readFile ../../config/claude/block-dangerous-git.sh;
    })
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
    (pkgs.writeShellApplication {
      name = "claude-paste-preview";
      runtimeInputs = with pkgs; [
        coreutils
        gnugrep
        imagemagick
        wl-clipboard
      ];
      text = builtins.readFile ../../config/claude/paste-preview.sh;
    })
  ];
  # Live link, because herdr rewrites its config itself.
  xdg.configFile."herdr/config.toml".source = live "herdr/config.toml";
}
