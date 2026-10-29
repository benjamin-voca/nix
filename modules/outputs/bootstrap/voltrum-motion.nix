{pkgs, lib}: {
  chartFiles = {};
  inlineFiles = {
    "30-voltrum-motion.yaml" = builtins.readFile ../../../apps/voltrum-motion/resources.json;
  };
  order = ["30-voltrum-motion.yaml"];
}
