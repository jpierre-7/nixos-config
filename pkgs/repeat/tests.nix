{
  callPackage,
  runCommandLocal,
  writeShellScriptBin,
}:
let
  fakeNotify = writeShellScriptBin "notify-send" ''
    echo "notify $*" >>"$NOTES"
  '';
  repeat = callPackage ./. { libnotify = fakeNotify; };
  # Logs its arguments one per line, between markers, so a lost or split argument shows.
  argv = writeShellScriptBin "argv" ''
    printf '[%s]\n' "$@" >>"$LOG"
  '';
in
runCommandLocal "repeat-tests"
  {
    nativeBuildInputs = [
      repeat
      argv
    ];
  }
  ''
    export HOME=$PWD/home NOTES=$PWD/notes LOG=$PWD/log
    mkdir -p "$HOME"
    touch "$NOTES" "$LOG"
    fail=0
    expect() {
      if [ "$1" != "$2" ]; then
        printf 'FAIL %s:\n  got      %s\n  expected %s\n' "$3" "$1" "$2"
        fail=1
      fi
    }

    repeat
    expect "$(cat "$NOTES")" "notify -a repeat Nothing to repeat no repeatable action has run yet" \
      "with no record, a notification and nothing else"
    expect "$(cat "$LOG")" "" "and nothing runs"

    repeat record argv "a file.opus" "it's \"quoted\"" '$(touch pwned) *' $'two\nlines' ""
    repeat
    expect "$(cat "$LOG")" "[a file.opus]
    [it's \"quoted\"]
    [\$(touch pwned) *]
    [two
    lines]
    []" "spaces, quotes, globs, newlines and empty arguments replay exactly"
    expect "$([ -e pwned ] && echo ran || echo safe)" safe "no argument is run by a shell"

    : >"$LOG"
    repeat
    repeat
    expect "$(grep -c 'a file.opus' "$LOG")" 2 "repeating again replays the same record"

    repeat record argv second
    : >"$LOG"
    repeat
    expect "$(cat "$LOG")" "[second]" "a new record overwrites the last"

    : >"$NOTES"
    repeat record gone-command x
    repeat
    expect "$(cat "$NOTES")" "notify -a repeat Nothing to repeat gone-command is no longer installed" \
      "a replay whose command is gone notifies"

    if [ "$fail" != 0 ]; then exit 1; fi
    touch $out
  ''
