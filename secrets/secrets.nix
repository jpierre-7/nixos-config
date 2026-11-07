# Who can decrypt each secret. Public keys only, read by the agenix CLI and
# never by the system build. How to add a secret or a machine is in SECURITY.md.
let
  desktop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOj0Ux8qZ2SQ48okMKjbDj+sTkbTQzbU1UDT2RLl8kL7";
  laptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA32N2BUp6kucXkJoKHWMMj7iRy8X3WoQJcK9/e1zma9";
  all = [
    desktop
    laptop
  ];
in
{
  "wake-desktop.age".publicKeys = all;
}
