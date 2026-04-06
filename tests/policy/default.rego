package main
import rego.v1

deny contains msg if {
  input.kind == "Application"
  not input.spec.syncPolicy.automated.prune
  msg := sprintf("Application %q must enable syncPolicy.automated.prune", [input.metadata.name])
}

deny contains msg if {
  input.kind == "Application"
  not input.spec.syncPolicy.automated.selfHeal
  msg := sprintf("Application %q must enable syncPolicy.automated.selfHeal", [input.metadata.name])
}

deny contains msg if {
  input.kind == "Application"
  not startswith(input.spec.destination.server, "https://")
  msg := sprintf("Application %q destination.server must use https", [input.metadata.name])
}

deny contains msg if {
  input.kind == "Application"
  not input.spec.destination.namespace
  msg := sprintf("Application %q must define destination.namespace", [input.metadata.name])
}
