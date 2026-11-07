# Secrets kept encrypted in secrets/ and decrypted to /run/agenix at activation.
# SECURITY.md covers adding a secret, adding a machine, and losing a key.
{ inputs, pkgs, ... }:
{
  imports = [ inputs.agenix.nixosModules.default ];

  # agenix defaults to the OpenSSH host keys, but neither host runs OpenSSH:
  # Tailscale SSH handles logins. So it uses the user key every machine has.
  age.identityPaths = [ "/home/john/.ssh/id_ed25519" ];

  environment.systemPackages = [
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
