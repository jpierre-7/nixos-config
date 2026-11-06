# Live flow graph of a Claude Code session (`zoe`). Not in nixpkgs. Source pinned
# by the `zoetrope` flake input.
{
  rustPlatform,
  src,
}:
rustPlatform.buildRustPackage {
  pname = "zoetrope";
  version = "0-unstable-${src.lastModifiedDate or "unknown"}";
  inherit src;
  cargoLock.lockFile = "${src}/Cargo.lock";
  # Fails in the build sandbox on its Codex fixture, after its Claude half passes.
  checkFlags = [ "--skip=provider::tests::open_finds_every_file_of_a_fixture_session" ];
  # Upstream's theme is fixed 256-palette colors. The terminal's own colors follow
  # the wallpaper (Noctalia writes them for WezTerm, modules/home/noctalia.nix), and
  # a replace that stops matching after an update fails the build instead of
  # quietly going back to black and gold. canvas_bg resets to the panes' background.
  postPatch = ''
    substituteInPlace src/state/graph.rs --replace-fail \
      'palette.accent = Color::Indexed(178);' \
      'palette.canvas_bg = Color::Reset;
    palette.surface = Color::Black;
    palette.muted = Color::DarkGray;
    palette.subtle = Color::DarkGray;
    palette.accent = Color::Yellow;
    palette.text = Color::Reset;
    palette.success = Color::Green;
    palette.error = Color::Red;'
    substituteInPlace src/ui/mod.rs \
      --replace-fail 'Color::Indexed(173)' 'Color::Magenta' \
      --replace-fail 'Color::Indexed(36)' 'Color::Cyan' \
      --replace-fail 'Color::Indexed(252)' 'Color::Gray' \
      --replace-fail 'MiniMap::new(&app.flow).position(MiniMapPosition::TopRight)' \
        'MiniMap::new(&app.flow).position(MiniMapPosition::TopRight).style(rataflow::MiniMapStyle::default().with_node_color(Color::Gray))'
    substituteInPlace src/autopilot.rs --replace-fail 'Color::Indexed(220)' 'Color::Yellow'
  '';

  meta.mainProgram = "zoe";
}
