---
name: friend-prompt
description: Write a copy-ready prompt that a friend pastes into their own AI agent to add a feature of this nixos-config to their setup. Use when the user runs /friend-prompt <feature...> or asks for a prompt, instructions, or a write-up so a friend can copy, port, or set up a feature of this config (bind palette, backlog, a niri bind, a Claude Code hook, and so on).
---

The friend's agent cannot see this machine. It sees only the public repo
https://github.com/jpierre-7/nixos-config and the prompt. So the prompt
points at the README section, the files, and the commits for each feature,
and tells the agent to adapt them to the friend's setup.

## 1. Find each feature

The arguments name one or more features. For each one:

- Find its README section (`grep -n '^#' README.md`). Its anchor is the
  heading in lowercase, with spaces as `-` and punctuation removed.
- Find its files: the paths that the README section names, then
  `grep -rl` over `modules/`, `pkgs/`, `config/`, `hosts/` and `flake.nix`.
  Keep only the files that the feature needs, not every file that mentions it.
- If you cannot tell which feature the user means, ask.

## 2. Find the commits

```bash
git fetch -q origin main
git log --reverse --format='%h %s' origin/main -- <files>
```

Use `origin/main`, because a commit that is only local is not on GitHub.
Remove commits that only touch the feature in passing (a repo-wide rename, a
`nix fmt` run, a change to a different feature in the same file). Read
`git show --stat <sha>` when you cannot tell. Each subject ends with its PR
number, `(#N)`. Keep the first commit, which adds the feature, and the fixes
after it.

## 3. Keep private data out

The prompt goes to other people. Do not put these in it:

- Anything in `secrets/`, or the contents of a file that a module decrypts.
  If the feature needs one, say what the friend supplies ("your own list of
  repos", "your own token") and how the repo keeps it out of git (agenix).
- `Planning:` lines, and any name or text from a private tracker that a PR
  body or commit message refers to.
- Email addresses, hostnames, IP addresses, and tailnet names. Describe them
  ("the other machine's address").

## 4. Other operating systems

The friend may not run NixOS. For each feature, add one `Not on NixOS:` line
when the feature can work elsewhere: the packages to install (pacman, brew),
and what replaces the Nix parts (a systemd user unit or launchd agent for a
service, a plain file in `~/.config` for a Home Manager file). Leave the line
out when the feature depends on Linux or on niri, or say what does the same
job there if that is clear (another compositor's bind syntax). Do not guess
package names: check them, or say "find the package for X".

## 5. Write the prompt

Print one fenced `text` block, wrapped at 80 columns, and nothing else
except one line under it that lists the features you put in. Shape:

```text
Adapt <feature, or "two tools"> from https://github.com/jpierre-7/nixos-config
(NixOS flake) into my own setup. First read my config to learn my OS,
compositor, launcher, shell and apps, then port each feature to them. Don't
copy one-to-one.

1. <feature>: <what it does for the person using it, one or two lines>.
   Read: README#<anchor>, <files>.
   Commits in order: <sha> (#N) <sha> (#N). The later commits are bug fixes,
   so include them.
   Not on NixOS: <packages and replacements>.

2. ...

Use `gh` or raw.githubusercontent.com to read files, and
`gh api repos/jpierre-7/nixos-config/commits/SHA` to read commit diffs.
Before writing code, show me a plan: where each piece goes in my config,
which hotkeys you'll use (checked for conflicts), and which dependencies
you'll install.
```

Leave out the "bug fixes" sentence when a feature has one commit, and the
hotkeys clause when no feature adds a key. If part of a feature is optional
(one of several data sources, a theme hook), say "include only the parts I
actually use".
