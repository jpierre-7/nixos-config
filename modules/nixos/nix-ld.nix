{
  # Lets prebuilt, dynamically linked Linux binaries run on NixOS. This is what
  # makes uv-managed Python (and the pip wheels with C extensions installed
  # into its venvs) work; see "Python projects" in the README.
  programs.nix-ld.enable = true;
}
