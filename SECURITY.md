# Secrets

This repo is public. Secrets live in `secrets/` as files encrypted with
[agenix](https://github.com/ryantm/agenix), and `secrets/secrets.nix` lists the
public keys that can read each one. Each machine decrypts them with its
`~/.ssh/id_ed25519` when it rebuilds, into `/run/agenix`.

Think of each secret as a locked box with one keyhole per machine. The public
keys in `secrets.nix` cut the keyholes, and the private key stays on the machine.

## Add a secret

1. Add `"name.age".publicKeys = all;` to `secrets/secrets.nix`.
2. Run `agenix -e name.age` from `secrets/`, type the value, save.
3. Run `git add secrets/name.age`, because flakes only see tracked files.
4. In the host's config, set `age.secrets.name.file = ../../secrets/name.age;`
   (and `owner = "john";` if your user needs to read it).
5. Use `config.age.secrets.name.path` in the config, not the value itself. A
   value in a Nix string ends up world-readable in `/nix/store`.

## Add a machine

1. Copy `~/.ssh/id_ed25519` to the new machine, or generate a new key there.
2. For a new key, add its public half to `secrets/secrets.nix`, then run
   `agenix -r` from `secrets/` on a machine that can already decrypt. Commit the result.
3. Rebuild the new machine. The key has to be there first, or decryption fails.

## Lose a key

- **Lost one machine's key:** another machine can still decrypt. Remove the lost
  key from `secrets/secrets.nix`, run `agenix -r`, and commit.
- **Key might be stolen:** do the same, and change each secret's real value too.
  Old encrypted copies stay in git history, and the stolen key opens those.
- **Lost every key:** the encrypted files can't be recovered. Generate a new key,
  delete the `.age` files, and create them again from the real values.

`wake-desktop.age` holds the router login on line 1 and the desktop's MAC address
on line 2. If it's ever lost, the login is in the router's admin panel, and
`ip link` on the desktop shows the MAC.

# Leak checks

- **Before a commit:** gitleaks and nixfmt run as a pre-commit hook. Run
  `nix develop` once on each machine to install it.
- **On GitHub:** `.github/workflows/gitleaks.yml` scans each push and pull
  request, plus commit messages and pull request text.
- **Rules:** `.gitleaks.toml` is public too, so its patterns stay generic. A
  pattern that names a private value publishes that value.

# Linking a pull request to a ticket

Put `Planning: 12` in the pull request body. Use the bare number: GitHub would
link `#12` to this repo's own issue or pull request 12.
