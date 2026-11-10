# block-dangerous-git: Claude Code PreToolUse hook (config/claude/settings.json)
# for the Bash tool. Packaged in modules/home/claude.nix; the git-guardrails
# check in flake.nix tests it.
#
# Based on block-dangerous-git.sh from mattpocock/skills, which can only block
# and matches exact wording, so `git -C path push` and `git clean -xdf` got
# through. A plain push asks the user here, so Claude can still push once they
# approve; anything destructive is blocked outright. gh gets the same prompt for
# what git can't see: merges, repo settings, and writes through its raw API. It's
# a guard against mistakes, not a sandbox: a script file that runs git isn't seen.
#
# It matches commands the shell will run, not text that only mentions them.
# Grepping the whole command blocked a commit message or a `cat > notes <<'EOF'`
# that named `git reset --hard`. shfmt parses the command; each simple command
# becomes one line of plain words, and only those lines are matched. Text that
# does run is parsed too: `bash -c`, `eval`, a heredoc fed to a shell, ssh,
# tmux, herdr panes, and $(...) anywhere. When the hook can't tell what will
# run, it falls back to grepping the whole text like before, and code it can't
# read at all (`bash -c "$cmd"`, `... | bash`) asks the user.

# A hook that can't read the command must not wave it through. Claude Code
# runs the command anyway when a hook fails with any exit code but 2, so a
# failure anywhere below blocks.
set -o errtrace
trap 'echo "BLOCKED: the git guardrail hook failed on this command. Stop and ask the user." >&2; exit 2' ERR

input=$(cat)
if ! cmd=$(jq -er '.tool_input.command' <<<"$input"); then
  echo "BLOCKED: couldn't read the command from the hook input." >&2
  exit 2
fi

# The jq half of the parse: walks shfmt's syntax tree and prints, one per line,
#   L<tab>words  a simple command that runs. Whitespace inside a word becomes _,
#                so a quoted "explain git push" can't read as three words.
#                $_ stands for a part only known at run time ($x, $(...)).
#   S<tab>json   shell code to parse next: a heredoc fed to bash, the args of
#                bash/eval/ssh. Their args are joined and parsed whole, which
#                also sees `bash script.sh` as harmless words.
#   O            something it can't see through, e.g. a command named by $x.
#   U            shell code it can't read, e.g. `bash -c "$cmd"`.
# Redirect ops 71/72 (<< and <<-) and 73 (<<<) are shfmt's internal numbers;
# the heredoc cases in the git-guardrails check catch a renumbering.
# shellcheck disable=SC2016 # $ in jq strings is jq's, not the shell's.
walk='
  def unesc($c): gsub("\\\\\n"; "") | gsub("\\\\(?<c>" + $c + ")"; .c);
  def part($dq):
    if .Type == "Lit" then .Value | if $dq then unesc("[$`\"\\\\]") else unesc(".") end
    elif .Type == "SglQuoted" then .Value
    elif .Type == "DblQuoted" then [.Parts[]? | part(true)] | if any(. == null) then null else join("") end
    else null end;
  def word: [.Parts[]? | part(false)] | if any(. == null) then null else join("") end;
  # A quoted delimiter (<<'"'"'EOF'"'"') leaves the body exactly as written.
  def hdoc:
    if [.Word.Parts[] | .Type == "Lit" and (.Value | contains("\\") | not)] | all
    then [.Hdoc.Parts[]? | part(true)] | if any(. == null) then null else join("") end
    else [.Hdoc.Parts[]?.Value] | join("") end;
  def stdin: [.Redirs[]? | if .Op == 71 or .Op == 72 then hdoc elif .Op == 73 then .Word | word else empty end];
  def code($a): if any($a[]; . == null) then "U" else "S\t" + ($a | join(" ") | tojson) end;

  .. | objects | select(.Cmd?.Type? == "CallExpr" and .Cmd.Args != null)
  | [.Cmd.Args[] | word] as $w
  | stdin as $in
  | ("L\t" + ($w | map(if . == null then "$_" elif . == "" then "\"\"" else gsub("[[:space:]]"; "_") end) | join(" "))),
    (if $w[0] == null then "O" else empty end),
    (range($w | length) as $i
     | ($w[$i] // "" | sub(".*/"; "")) as $name
     | $w[$i + 1:] as $a
     | if $name | IN("bash", "sh", "zsh", "dash", "ksh", "mksh", "fish") then
         code($a),
         ($in[] | if . == null then "U" else "S\t" + tojson end),
         # No -c and no script file (or -s): the shell runs whatever is on stdin.
         (if ($in | length) == 0 and (any($a[]; . != null and test("^(-[[:alpha:]]*c[[:alpha:]]*|--command)$")) | not)
             and (all($a[]; . != null and test("^[-+]")) or any($a[]; . != null and test("^-[[:alpha:]]*s[[:alpha:]]*$")))
          then "U" else empty end)
       elif $name | IN("eval", "ssh", "watch", "su", "runuser", "sg", "nix-shell", "parallel", "tmux", "herdr") then
         code($a),
         ($in[] | if . == null then "U" else "S\t" + tojson end)
       # git runs these as shell code: rebase --exec, submodule foreach, ! aliases.
       elif $name == "git" and any($a[]; . != null and (. == "rebase" or . == "submodule" or startswith("alias."))) then
         "O"
       else empty end)
'

lines=()       # every simple command that will run, as plain words
opaque=false   # fall back to grepping the whole command
unknown=false  # some shell code can't be read: ask at least

# $1: shell code, $2: how deeply it is nested in other shell code.
analyze() {
  local ast out tag val
  if (($2 > 8)) || ! ast=$(shfmt -ln bash --to-json <<<"$1" 2>/dev/null); then
    opaque=true
    return
  fi
  # Not `done < <(jq ...)`: a failing jq there would go unnoticed.
  out=$(jq -r "$walk" <<<"$ast")
  [[ -n $out ]] || return 0
  while IFS=$'\t' read -r tag val; do
    case $tag in
      L) lines+=("$val") ;;
      S) analyze "$(jq -r . <<<"$val")" $(($2 + 1)) ;;
      U) unknown=true opaque=true ;;
      *) opaque=true ;;
    esac
  done <<<"$out"
}
analyze "$cmd" 0

# The old whole-text view. `git \<newline> push` is the same command.
text=${cmd//$'\\\n'/ }
text=${text//$'\n'/ }

sp='[[:space:]]'
# $1: what may come right before git or gh. $2: the rest of one command.
# Sets block_patterns and ask_patterns, which matches reads through a nameref.
# shellcheck disable=SC2034 # shellcheck can't follow the nameref.
make_patterns() {
  # git, then any global options (-C path, -c x=y, --no-pager), then the subcommand.
  local git="$1git($sp+-[^[:space:]]+($sp+(\"[^\"]*\"|'[^']*'|[^[:space:]]+))?)*$sp+"
  local gh="$1gh$sp+" rest=$2
  block_patterns=(
    "${git}push$rest$sp(--force|-[[:alpha:]]*f)"
    "${git}push$rest$sp\+[^[:space:]]"
    "${git}reset$rest$sp--hard"
    "${git}clean$rest$sp(--force|-[[:alpha:]]*f)"
    "${git}branch$rest$sp-[[:alpha:]]*D"
    "${git}branch$rest$sp(-d|--delete)$sp$rest(-f|--force)"
    "${git}branch$rest$sp(-f|--force)$sp$rest(-d|--delete)"
    "${git}checkout$rest$sp\.($sp|/|$|[\"'])"
    "${git}restore$rest$sp\.($sp|/|$|[\"'])"
    "${git}filter-(repo|branch)"
    "$1git-filter-repo"
  )
  ask_patterns=(
    "${git}push([^[:alnum:]_-]|$)"
    "${gh}pr$sp+merge"
    "${gh}repo$sp+(delete|edit|rename|archive)"
    "${gh}(issue|release)$sp+delete"
    "${gh}secret"
    "${gh}api$rest$sp(-X|--method)[=[:space:]]*(POST|PUT|PATCH|DELETE)"
    "${gh}api$rest$sp(-[fF]|--field|--raw-field|--input)"
  )
}

# The checks: parsed lines, then the whole text when parsing didn't settle it.
# In a parsed line, git is a whole word (or a path ending in /git), and a line
# is one command, so its flags run to the end. In the raw text, git is anything
# not glued to a name, and a command stops at ; & |.
checks=(word)
if $opaque; then checks+=(text); fi
# $1: word or text. $2: block or ask. Succeeds if a pattern matches.
matches() {
  local subject pattern flags=()
  local -n list=${2}_patterns
  # Block patterns are case-sensitive: `branch -D` deletes, `branch -d` doesn't.
  if [[ $2 == ask ]]; then flags=(-i); fi
  if [[ $1 == word ]]; then
    make_patterns "(^|$sp)([^[:space:]]*/)?" '.*'
    subject=$(printf '%s\n' "${lines[@]}")
  else
    make_patterns '(^|[^[:alnum:]_.-])' '[^;&|]*'
    subject=$text
  fi
  for pattern in "${list[@]}"; do
    if grep -q "${flags[@]}" -E -- "$pattern" <<<"$subject"; then
      return 0
    fi
  done
  return 1
}

ask() {
  jq -n --arg why "$1" '{hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $why
  }}'
  exit 0
}

for check in "${checks[@]}"; do
  if matches "$check" block; then
    echo "BLOCKED: '$cmd' is a destructive git command. The user has prevented you from doing this. Stop and ask them." >&2
    exit 2
  fi
done
for check in "${checks[@]}"; do
  if matches "$check" ask; then
    ask "This command needs the user's approval"
  fi
done
if $unknown; then
  ask "This command runs shell code the git guardrail can't read"
fi
