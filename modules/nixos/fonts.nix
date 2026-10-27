{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    noto-fonts
    # Arch's noto-fonts-emoji; the old nixpkgs name is an error on 26.05.
    noto-fonts-color-emoji
    # "Maple Mono" is the font WezTerm and Noctalia ask for; the Nerd Font
    # builds carry the icon glyphs Starship, lsd and fastfetch use.
    maple-mono.truetype
    maple-mono.NF-unhinted
    maple-mono.NF-CN-unhinted
  ];
}
