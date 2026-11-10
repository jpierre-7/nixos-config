# claude-paste-preview: prints a thumbnail of the image on the clipboard, for
# the pasted-image-preview mod (config/claude/mods/pasted-image-preview/).
#
# Claude Code keeps a pasted image in memory and lets a mod read its bytes only
# once the prompt is submitted, too late for a preview. Ctrl+V attaches the
# clipboard's image, so the mod runs this right after an [Image #N] lands in the
# prompt box and shows what the clipboard held at that moment. A copied path to
# an image file (text, or a file manager's file:// URI) is read the same way.
#
# Output: the original size (WIDTHxHEIGHT) on the first line, then the
# thumbnail as one line of base64 PNG. Exits 1 when there is no image.
#
# Packaged with writeShellApplication in modules/home/claude.nix.

max=${1:-480}
types=$(wl-paste --list-types 2>/dev/null || true)
src=$(mktemp)
trap 'rm -f "$src"' EXIT

if mime=$(grep -m1 -E '^image/(png|jpeg|jpg|gif|webp|bmp)$' <<<"$types"); then
  wl-paste --no-newline --type "$mime" >"$src"
elif grep -qxE 'text/uri-list|text/plain(;charset=utf-8)?' <<<"$types"; then
  # One file: the first line, without file:// or quotes, %XX decoded.
  path=$(wl-paste --no-newline 2>/dev/null | head -n1 | tr -d '\r')
  path=${path#file://}
  path=${path#[\"\']}
  path=${path%[\"\']}
  path=$(printf '%b' "${path//%/\\x}")
  [[ $path == /* && -f $path ]] || exit 1
  cp -- "$path" "$src"
else
  exit 1
fi

# [0]: the first frame of a GIF. identify fails on anything that isn't an image.
size=$(magick identify -format '%wx%h' "${src}[0]" 2>/dev/null) || exit 1
echo "$size"
magick "${src}[0]" -resize "${max}x${max}>" png:- | base64 -w0
echo
