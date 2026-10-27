# Home Manager entry point for john (same on every host). Host-specific
# user settings go in hosts/<host>/default.nix under home-manager.users.john.
{
  imports = [ ../modules/home ];

  # Home Manager release this user was first set up with. Like
  # system.stateVersion, leave it alone on upgrades.
  home.stateVersion = "26.05";
}
