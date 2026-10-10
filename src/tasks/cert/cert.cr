# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "Run the essential tests; exits 0 when enough of them pass (the threshold)"
# Compatibility runs last: scaling and rolling out change the CNF, and what a
# change leaves behind (a scaled-in database cluster that stays degraded)
# must not fail a test that judges something else (#2719).
suite_task "cert", ["version", "cert_state", "cert_security", "cert_configuration", "cert_observability", "cert_microservice", "cert_resilience", "cert_compatibility"],
  scope: "essential",
  min_passed: ESSENTIAL_PASSED_THRESHOLD,
  max_failed: CNFManager::NO_FAILURE_LIMIT,
  summary: false do  |_, args|
  Log.debug { "cert" }

  stdout_success "RESULTS SUMMARY"
  total = CNFManager::Points.total_points("cert")
  max_points = CNFManager::Points.total_max_points("cert")
  total_passed = CNFManager::Points.total_passed("cert")
  max_passed = CNFManager::Points.total_max_passed("cert")
  essential_total_passed = CNFManager::Points.total_passed("essential")
  essential_max_passed = CNFManager::Points.total_max_passed("essential")
  max_passed = essential_max_passed if args.raw.includes? "essential"
  stdout_success "  - #{total_passed} of #{max_passed} total tests passed"

  if essential_total_passed >= ESSENTIAL_PASSED_THRESHOLD
    stdout_success "  - #{essential_total_passed} of #{essential_max_passed} essential tests passed"
  else
    stdout_failure "  - #{essential_total_passed} of #{essential_max_passed} essential tests passed"
  end

end
