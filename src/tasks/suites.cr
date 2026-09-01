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
suite_task "workload", ["compatibility", "state", "security", "configuration",
                        "observability", "microservice", "resilience"]
