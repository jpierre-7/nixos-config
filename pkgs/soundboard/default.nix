# A soundboard with no app, ported from the sound half of HefKer/nixos-config's
# pkgs/memes. sound-add saves a link's or file's audio into the library,
# sound-pick plays a pick into the "Soundboard mic" (modules/nixos/audio.nix),
# which carries your voice too, sound-stop cuts it off, and sound-volume sets
# the volumes without a rebuild. Called from modules/home/soundboard.nix.
{
  callPackage,
  coreutils,
  ffmpeg,
  findutils,
  fuzzel,
  gawk,
  glib,
  gnused,
  lib,
  libnotify,
  pipewire,
  symlinkJoin,
  util-linux,
  wl-clipboard,
  writeShellApplication,
  yt-dlp,
  # Where sounds are saved.
  library,
  # The PipeWire sink whose loopback is the soundboard mic voice chat records from.
  sink,
}:
# vicinae and noctalia come from PATH: the configured, running ones.
let
  # The repeat key's recorder (pkgs/repeat/): sound-pick and sound-add record their replay.
  repeat = callPackage ../repeat { };
  # One line per playing sound: "<call PID> <you PID>". sound-pick writes it, sound-stop kills them.
  pids = ''"''${XDG_RUNTIME_DIR:-/tmp}/sound-pick.pids"'';
  # Held while the PID file is read and rewritten, and a PID is only trusted while /proc says it is
  # still pw-play, as a PID left in the file can be reused by another process.
  pidsTools = ''
    exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/sound-pick.lock"
    flock 9
    playing() { [ "$(cat /proc/"$1"/comm 2>/dev/null)" = pw-play ]; }
    stop_all() {
      local p
      for p in $(cat ${pids} 2>/dev/null || true); do
        ! playing "$p" || kill "$p" 2>/dev/null || true
      done
      rm -f -- ${pids}
    }
  '';
  # sound-volume writes "<call %> <you %>" here and sound-pick reads it on every pick; per machine, as mics differ.
  volumeFile = ''"''${XDG_CONFIG_HOME:-$HOME/.config}/soundboard/volume"'';
  defaultVolume = "20 20";

  soundAdd = writeShellApplication {
    name = "sound-add";
    runtimeInputs = [
      coreutils
      ffmpeg
      findutils
      fuzzel
      gawk
      glib
      gnused
      libnotify
      repeat
      wl-clipboard
      yt-dlp
    ];
    text = ''
      library=${lib.escapeShellArg library}
      src=''${1:-$(wl-paste --no-newline 2>/dev/null || true)}
      fail() { notify-send -a soundboard "Sound not saved" "$1"; exit 1; }
      [ -n "$src" ] || fail "no URL or file given, and the clipboard is empty"

      tmp=$(mktemp -d)
      # A download can take seconds before the first prompt, so a notification says it is underway until then.
      cue=""
      uncue() {
        [ -z "$cue" ] || gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
          --method org.freedesktop.Notifications.CloseNotification "$cue" >/dev/null 2>&1 || true
        cue=""
      }
      trap 'uncue; rm -rf "$tmp"' EXIT
      [ -f "$src" ] || cue=$(notify-send -p -t 0 -a soundboard "Fetching sound…" "$src" || true)

      # Typed text goes through fuzzel, as Vicinae's dmenu never returns it (like pkgs/backlog/). Its
      # colors are Noctalia's fuzzel template, rendered now if it isn't yet; fuzzel's own are solarized light.
      theme=''${XDG_CONFIG_HOME:-$HOME/.config}/fuzzel/themes/noctalia
      [ -r "$theme" ] || noctalia msg templates-apply >/dev/null 2>&1 || true
      conf=()
      [ ! -r "$theme" ] || conf=(--config "$theme")
      ask() { fuzzel "''${conf[@]}" --dmenu --prompt-only "$@" </dev/null; }

      if [ -f "$src" ]; then
        file=$src
        title=$(basename -- "''${src%.*}")
      else
        title=$(yt-dlp -q --no-warnings --no-playlist --no-simulate -f bestaudio/best --print title \
          -o "$tmp/media.%(ext)s" "$src") || fail "yt-dlp could not download $src"
        files=("$tmp"/media.*)
        [ -f "''${files[0]}" ] || fail "nothing was downloaded from $src"
        file=''${files[0]}
      fi

      uncue
      # Blank or Esc keeps the whole clip; otherwise start-end in anything ffmpeg reads as a time (5, 1:02.5).
      trim=$(ask "trim start-end (blank = all): ") || trim=""
      cut=()
      if [ -n "$trim" ]; then
        [[ $trim == *-* ]] || fail "trim must be start-end, got $trim"
        start=''${trim%%-*} end=''${trim#*-}
        [ -z "$start" ] || cut+=(-ss "$start")
        [ -z "$end" ] || cut+=(-to "$end")
      fi

      # Tags, seeded from the title with repeated words dropped; Esc saves nothing.
      suggest=$(tr -cs '[:alnum:]' '\n' <<<"$title" | tr '[:upper:]' '[:lower:]' | awk 'NF && !seen[$0]++' | paste -sd ' ')
      tags=$(ask "tags: " --search "$suggest") || exit 0
      # Names keep to [a-z0-9-], shown in the picker with spaces for dashes.
      name=$(tr '[:upper:]' '[:lower:]' <<<"$tags" | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-200)
      [ -n "$name" ] || name=sound
      mkdir -p "$library"
      # Repeated tags number all of their files: name-1.opus, name-2.opus, ...
      n=$(find "$library" -maxdepth 1 -type f -regextype posix-extended -regex ".*/$name(-[0-9]+)?\.[^.]+" -printf '%f\n' |
        sed -E "s/^$name-?//; s/\.[^.]+$//; s/^$/0/" | sort -n | tail -1)
      if [ -z "$n" ]; then
        dest="$library/$name.opus"
      else
        # An unnumbered one, saved before there was a second, takes the next number.
        for f in "$library/$name".*; do
          [ -f "$f" ] || continue
          n=$((n + 1))
          mv -n -- "$f" "$library/$name-$n.''${f##*.}"
        done
        dest="$library/$name-$((n + 1)).opus"
      fi

      # Opus because pw-play can't read m4a, YouTube's usual audio; loudnorm keeps clips from different sources at one level.
      ffmpeg -loglevel error -y "''${cut[@]}" -i "$file" -vn -af loudnorm -c:a libopus -b:a 96k "$dest" ||
        { rm -f -- "$dest"; fail "ffmpeg could not convert $src"; }
      notify-send -a soundboard "Sound saved" "$(basename "$dest")"
      # Replayed bare, so a repeat reads the clipboard afresh: copy the next link, repeat.
      [ "$#" -gt 0 ] || repeat record sound-add
    '';
  };

  soundPick = writeShellApplication {
    name = "sound-pick";
    runtimeInputs = [
      coreutils
      findutils
      gawk
      libnotify
      pipewire
      repeat
      util-linux
    ];
    text = ''
      library=${lib.escapeShellArg library}
      # Plays $1 to the call and to you, cutting off what is playing, and makes it the repeat's replay.
      play() {
        local vcall vyou call
        read -r vcall vyou _ 2>/dev/null <${volumeFile} || read -r vcall vyou <<<"${defaultVolume}"
        vyou=''${vyou:-$vcall}
        ${pidsTools}
        # Inside the lock, so two quick picks can't both survive.
        stop_all
        # Once into the soundboard mic for the call and once to the default output for you; 9>&- so pw-play doesn't hold the lock.
        pw-play --volume "$(awk -v p="$vcall" 'BEGIN { print p / 100 }')" --target ${lib.escapeShellArg sink} "$1" 9>&- &
        call=$!
        pw-play --volume "$(awk -v p="$vyou" 'BEGIN { print p / 100 }')" "$1" 9>&- &
        echo "$call $!" >${pids}
        exec 9>&-
        repeat record sound-pick --play "$1"
      }

      # sound-pick --play FILE: the repeat's replay, with no menu.
      if [ $# -gt 0 ]; then
        [ "$# $1" = "2 --play" ] || { echo "usage: sound-pick [--play FILE]" >&2; exit 1; }
        if [ ! -f "$2" ]; then
          notify-send -a soundboard "Sound gone" "$(basename "$2") is no longer in the library"
          exit 0
        fi
        play "$2"
        exit 0
      fi

      # Newest first, so what was just added is on top before anything is typed.
      mapfile -t files < <(find "$library" -maxdepth 1 -type f ! -name '.*' -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2-)
      if [ ''${#files[@]} -eq 0 ]; then
        notify-send -a soundboard "No sounds yet" "Copy a link and run sound-add (Mod+Shift+G)"
        exit 0
      fi

      # The row is the name with spaces for dashes, and its extension unless opus, so a hand-added
      # name.mp3 and name.opus stay apart. Vicinae prints the picked row, so it maps back by label.
      labels=()
      for f in "''${files[@]}"; do
        base=$(basename "$f")
        label=''${base%.*}
        label=''${label//-/ }
        [[ $base == *.opus ]] || label+=" (''${base##*.})"
        labels+=("$label")
      done
      pick=$(printf '%s\n' "''${labels[@]}" |
        vicinae dmenu --no-quick-look --no-footer -n soundboard -p "search sounds") || exit 0
      file=""
      for i in "''${!labels[@]}"; do
        if [ "''${labels[i]}" = "$pick" ]; then
          file=''${files[i]}
          break
        fi
      done
      [ -n "$file" ] || exit 0
      play "$file"
    '';
  };

  soundStop = writeShellApplication {
    name = "sound-stop";
    runtimeInputs = [
      coreutils
      util-linux
    ];
    text = ''
      ${pidsTools}
      stop_all
    '';
  };

  soundVolume = writeShellApplication {
    name = "sound-volume";
    runtimeInputs = [ coreutils ];
    text = ''
      # sound-volume prints the volumes; sound-volume CALL [YOU] sets them in percent, YOU defaulting to CALL.
      file=${volumeFile}
      if [ $# -eq 0 ]; then
        read -r vcall vyou _ 2>/dev/null <"$file" || read -r vcall vyou <<<"${defaultVolume}"
        echo "call ''${vcall}%, you ''${vyou:-$vcall}%"
        exit 0
      fi
      [ $# -le 2 ] || { echo "usage: sound-volume [CALL% [YOU%]]" >&2; exit 1; }
      for v in "$@"; do
        [[ $v =~ ^[0-9]+$ ]] || { echo "usage: sound-volume [CALL% [YOU%]], whole numbers" >&2; exit 1; }
      done
      mkdir -p "$(dirname "$file")"
      echo "$1 ''${2:-$1}" >"$file"
      echo "call $1%, you ''${2:-$1}%"
    '';
  };
in
symlinkJoin {
  name = "soundboard";
  paths = [
    soundAdd
    soundPick
    soundStop
    soundVolume
  ];
  meta.mainProgram = "sound-pick";
}
