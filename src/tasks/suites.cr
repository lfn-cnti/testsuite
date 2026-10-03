require "sam"
require "colorize"
require "./utils/utils.cr"

# `all` has no tag of its own - no test carries one - so its criterion and its
# score cover every test that ran rather than a tag's worth.
desc "Run every test"
suite_task "all", ["workload"],
  title: "",
  scope: CNFManager::EVERY_TEST

desc "Run every workload test against the installed CNF"
# Compatibility runs last: scaling, rolling updates and rollbacks change the
# CNF, and what a change leaves behind must not fail a test that judges
# something else (#2719).
suite_task "workload", ["state", "security", "configuration", "observability",
                        "microservice", "resilience", "compatibility"]
