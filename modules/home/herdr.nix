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
  herdrApp = pkgs.callPackage ../../pkgs/herdr-app.nix { };
  # Pixel HQ (inputs.pixel-hq): the layout's update check is cut, because its
  # "Update now" writes new files over its own mods, which are store links here.
  # Deleting version.json, as its README says, doesn't stop the check: it then
  # counts as 1.0.0 and always finds an update. Move the input instead.
  pixelHq = pkgs.runCommand "pixel-hq" { } ''
    mkdir $out
    cp -r ${inputs.pixel-hq}/{layouts,mods,themes} $out
    chmod -R u+w $out
    substituteInPlace $out/mods/company-agents/updater.js --replace-fail \
      'export async function checkPixelHqUpdate(notifyUser = true) {' \
      'export async function checkPixelHqUpdate(notifyUser = true) { return null;'
  '';
in
{
  # On PATH for the first dock of a running session: herdr only runs a plugin's
  # startup hook when its server starts.
  #
  # zoe: prefix+Z opens the focused agent's session as a graph, through the
  # plugin linked below, which finds zoe and jq (dev.nix) on PATH.
  #
  # herdr-app: herdr's desktop app (pkgs/herdr-app.nix). It drives herdr-core
  # (`hc`, unstable), a separate daemon from the herdr TUI, and finds it on PATH.
  # The app only updates a core it installed itself, so this one moves with
  # nixpkgs.
  home.packages = [
    agentCards
    zoetrope
    herdrApp
    pkgs.herdr-core
    # Pixel HQ's MusicBox plays YouTube links through it; without it, it offers
    # to install it with apt or pip.
    pkgs.yt-dlp
  ];

  # Pixel HQ: one link per mod folder, so herdr-app can still write its own
  # files (layouts/.state, pixel-hq-names.json) next to them.
  xdg.configFile =
    lib.mapAttrs' (
      name: _: lib.nameValuePair "herdr-app/mods/${name}" { source = "${pixelHq}/mods/${name}"; }
    ) (builtins.readDir "${inputs.pixel-hq}/mods")
    // {
      "herdr-app/layouts/pixel-hq.json".source = "${pixelHq}/layouts/pixel-hq.json";
      "herdr-app/themes/pixel-hq.json".source = "${pixelHq}/themes/pixel-hq.json";
    };

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
