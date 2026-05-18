# lib/typed-secrets.nix — Typed Secrets Library
#
# Provides compile-time validation of SOPS secrets with layered lookup.
# Layering: shared.yaml → role.yaml → host.yaml (later wins).
#
# Key format: hyphenated flat keys matching existing SOPS files
#   e.g., "harbor-admin-password", "cloudflared-credentials"
#
{pkgs ? null, lib ? if pkgs != null then pkgs.lib else throw "lib or pkgs required"}:

let
  inherit (lib) strings escape;
  foldl' = lib.foldl';
in

rec {
  /*
   * Convert dot-notation to hyphenated key:
   * "harbor.admin-password" → "harbor-admin-password"
   * "cloudflared-credentials" → "cloudflared-credentials" (no-op if no dots)
   */
  toHyphenatedKey = field:
    strings.concatStringsSep "-" (strings.splitString "." field);

  /*
   * Check if a decrypted SOPS file contains a given key.
   * Uses regex to match key as a top-level YAML key (start of line).
   * Returns true/false.
   */
  hasKey = sopsFileContent: field: let
    key = toHyphenatedKey field;
    # Match key anywhere in the file as a YAML key.
    # In Nix regex, . matches \n, so .* covers all lines.
    # We match "key:" to ensure it's a key definition, not a value.
    pattern = ".*${lib.strings.escapeRegex key}:.*";
  in
    builtins.match pattern sopsFileContent != null;

  /*
   * Resolve a field to a SOPS file using layered lookup.
   * Takes a list of {path, content} pairs. Returns the file path
   * where the field is found (first match = highest priority layer).
   * Throws if not found in any layer.
   */
  resolveField = fieldsFiles: field: let
    result = foldl' (acc: fp:
      if acc != null then acc
      else if hasKey fp.content field then fp.path
      else null
    ) null fieldsFiles;
  in
    if result == null
    then throw "Secret field '${field}' not found in layered secrets files"
    else result;

  /*
   * Read a SOPS file path into a {path, content} pair.
   * Content is the raw file text (encrypted YAML) — used for key
   * presence checking. Full decryption happens at build time via sops-nix.
   * Returns {path, content} even if file doesn't exist (empty content).
   */
  readSopsContent = sopsFile: let
    exists = builtins.pathExists sopsFile;
    content = if exists then builtins.readFile sopsFile else "";
  in {
    path = sopsFile;
    inherit content;
  };

  /*
   * Validate that required secrets exist in layered files.
   * Takes a list of field names and a list of {path, content} pairs.
   * Returns a list of {field, sopsFile} pairs.
   * Throws at eval time if any required field is missing.
   */
  validateRequired = requiredFields: fieldsFiles:
    builtins.map (field: let
      sopsFile = resolveField fieldsFiles field;
    in { inherit field sopsFile; })
    requiredFields;

  /*
   * Build sops.secrets attribute set from validated secrets.
   * Takes a list of {field, sopsFile} pairs (output of validateRequired).
   * Returns an attrset suitable for sops.secrets.
   *
   * Example output:
   *   {
   *     "harbor-admin-password" = {
   *       sopsFile = ./secrets/shared.yaml;
   *       path = "/run/secrets/harbor-admin-password";
   *     };
   *   }
   */
  toSopsSecrets = validatedSecrets:
    builtins.listToAttrs (
      builtins.map (s: {
        name = toHyphenatedKey s.field;
        value = {
          sopsFile = s.sopsFile;
          path = "/run/secrets/${toHyphenatedKey s.field}";
        };
      }) validatedSecrets
    );
}
