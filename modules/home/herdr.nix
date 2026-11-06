# Agent cards: a herdr plugin that draws spaces and agents (costumed pixel bots) in
# a panel at the left of every tab (config/herdr/agent-cards/). The rest of
# herdr's setup is in claude.nix.
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  agentCards = pkgs.writers.writePython3Bin "herdr-agent-cards" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ../../config/herdr/agent-cards/agent_cards.py);
  # Its own store directory, because herdr resolves symlinks when it links a
  # plugin: a Home Manager link to the manifest would make all of /nix/store the
  # plugin's root.
  plugin = pkgs.writeTextFile {
    name = "herdr-agent-cards-plugin";
    destination = "/herdr-plugin.toml";
    text = builtins.replaceStrings [ "@bin@" ] [ (lib.getExe agentCards) ] (
      builtins.readFile ../../config/herdr/agent-cards/herdr-plugin.toml
    );
  };
  zoetrope = pkgs.callPackage ../../pkgs/zoetrope.nix { src = inputs.zoetrope; };
in
{
  # On PATH for the first dock of a running session: herdr only runs a plugin's
  # startup hook when its server starts.
  #
  # zoe: prefix+Z opens the focused agent's session as a graph, through the
  # plugin linked below, which finds zoe and jq (dev.nix) on PATH.
  home.packages = [
    agentCards
    zoetrope
  ];

  # Each rebuild has a new store path, so link it again to replace the old one,
  # which garbage collection can then remove. A failure here (say, a newer
  # manifest than the running herdr) shouldn't stop the whole activation.
  home.activation.linkHerdrAgentCards = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe pkgs.herdr} plugin link ${plugin} >/dev/null || true
    # A link skips the plugin's build hook, which would install zoe with
    # Homebrew or cargo.
    run ${lib.getExe pkgs.herdr} plugin link ${inputs.zoetrope}/herdr-plugin >/dev/null || true
  '';
}
