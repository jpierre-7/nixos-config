# block-dangerous-git: Claude Code PreToolUse hook (config/claude/settings.json)
# for the Bash tool. Packaged in modules/home/claude.nix; the git-guardrails
# check in flake.nix tests it.
#
# Based on block-dangerous-git.sh from mattpocock/skills, which can only block
# and matches exact wording, so `git -C path push` and `git clean -xdf` got
# through. A plain push asks the user here, so Claude can still push once they
# approve; anything destructive is blocked outright. It's a guard against
# mistakes, not a sandbox: a script file that runs git isn't seen.

input=$(cat)
# A hook that can't read the command must not wave it through.
if ! cmd=$(jq -er '.tool_input.command' <<<"$input"); then
  echo "BLOCKED: couldn't read the command from the hook input." >&2
  exit 2
fi
# `git \<newline> push` is the same command.
cmd=${cmd//$'\\\n'/ }
cmd=${cmd//$'\n'/ }

# git, then any global options (-C path, -c x=y, --no-pager), then the subcommand.
sp='[[:space:]]'
git="(^|[^[:alnum:]_.-])git($sp+-[^[:space:]]+($sp+(\"[^\"]*\"|'[^']*'|[^[:space:]]+))?)*$sp+"
# The rest of this one command: stop at ; & | so a later command's flags don't count.
# The patterns also end at a quote, for `bash -c "git push"`.
rest='[^;&|]*'

patterns=(
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
  "git-filter-repo"
)

for pattern in "${patterns[@]}"; do
  if grep -qE -- "$pattern" <<<"$cmd"; then
    echo "BLOCKED: '$cmd' is a destructive git command. The user has prevented you from doing this. Stop and ask them." >&2
    exit 2
  fi
done

if grep -qE -- "${git}push([^[:alnum:]_-]|$)" <<<"$cmd"; then
  jq -n '{hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: "git push needs the user'"'"'s approval"
  }}'
fi
