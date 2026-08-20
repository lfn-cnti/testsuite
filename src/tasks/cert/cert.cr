# coding: utf-8
require "sam"
require "file_utils"
require "colorize"
require "totem"
require "../utils/utils.cr"

desc "The CNF Test Suite program certifies a CNF based on passing some percentage of essential tests."
task "cert", ["version", "cert_compatibility", "cert_state", "cert_security", "cert_configuration", "cert_observability", "cert_microservice", "cert_resilience"] do  |_, args|
  Log.debug { "cert" }

  # `cert` is judged by its certification criterion rather than by individual
  # test failures, so the run exits 0 exactly when the CNF is certified.
  # See Points.write_summary! for the derivation.
  CNFManager::Points.pass_threshold = ESSENTIAL_PASSED_THRESHOLD

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
    stdout_failure "Certification failed! Passing threshold is #{ESSENTIAL_PASSED_THRESHOLD} essential tests"
  end

  CNFManager::Points.write_summary!
  stdout_info "Results have been saved to #{CNFManager::Points::Results.file}".colorize(:green)
end
