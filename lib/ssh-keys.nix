# SSH public keys used across the homelab
# - Used by agenix (secrets/secrets.nix) for encryption
# - Used by installer ISO for authorized_keys
{
  # jankaifer
  jankaifer-1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJe9IWxd3nIG9qm86UMTZeVHHeHN5eh6nHu7KwU+x/fz";
  jankaifer-2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFQZcA7EKUH91Sp4s2aRNJ6sOgZCUx9CqDuaEiPvWjWC";
  # jk-cf
  jk-cf = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG6x4L/uYrM/KmYBTvvl3FaO2T3T5Vf+uAnEKKA43BwU";
}
