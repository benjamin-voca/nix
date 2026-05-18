# tests/nix/machines/registry-test.nix
#
# Validates the structure of machines/default.nix.
# Run: nix-instantiate --eval tests/nix/machines/registry-test.nix
#
# Returns: true if all checks pass, throws on failure.

let
  registry = import ../../../machines/default.nix;

  # --- Machine checks ---
  machineNames = builtins.attrNames registry.machines;
  roleNames = builtins.attrNames registry.roles;

  # Required machine fields
  requiredMachineFields = [ "system" "hardware" "role" ];

  # Required role fields
  requiredRoleFields = [ "module" ];

  # Validate a single machine
  validateMachine = name: machine:
    let
      # Check required fields exist
      missingFields = builtins.filter (f: !builtins.hasAttr f machine) requiredMachineFields;
    in
    if missingFields != []
    then throw "Machine '${name}' is missing required fields: ${builtins.concatStringsSep ", " missingFields}"
    else if !builtins.elem machine.role roleNames
    then throw "Machine '${name}' references unknown role '${machine.role}'. Available: ${builtins.concatStringsSep ", " roleNames}"
    else if machine.system != "x86_64-linux"
    then throw "Machine '${name}' has unexpected system '${machine.system}'. Expected 'x86_64-linux'."
    else true;

  # Validate a single role
  validateRole = name: role:
    let
      missingFields = builtins.filter (f: !builtins.hasAttr f role) requiredRoleFields;
    in
    if missingFields != []
    then throw "Role '${name}' is missing required fields: ${builtins.concatStringsSep ", " missingFields}"
    else true;

  # Validate all machines
  machineResults = builtins.mapAttrs validateMachine registry.machines;

  # Validate all roles
  roleResults = builtins.mapAttrs validateRole registry.roles;

  # Check that machine names match expected hosts
  expectedMachines = [ "backbone-01" "frontline-01" ];
  missingMachines = builtins.filter (m: !builtins.elem m machineNames) expectedMachines;
  extraMachines = builtins.filter (m: !builtins.elem m expectedMachines) machineNames;

in
  if missingMachines != []
  then throw "Missing expected machines: ${builtins.concatStringsSep ", " missingMachines}"
  else if extraMachines != []
  then throw "Unexpected machines in registry: ${builtins.concatStringsSep ", " extraMachines}"
  else if !builtins.elem "backbone" roleNames
  then throw "Missing required role 'backbone'"
  else if !builtins.elem "worker" roleNames
  then throw "Missing required role 'worker'"
  else true
