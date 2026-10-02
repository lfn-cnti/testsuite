require "sam"
require "./server"

desc "Run an MCP (JSON-RPC 2.0 over stdio) server exposing the suite to AI agents; see USAGE.md"
task "mcp" do |_, args|
  # No install or uninstall by default: cnf_install/cnf_uninstall are exposed
  # only with --allow-install.
  allow_install = args.raw.includes?("allow_install")
  # The runs are children of this server, so a --results-dir given here is
  # passed on to them (CNTI_TESTSUITE_RESULTS_DIR reaches them as it is).
  results_dir = CLIInvocation.option(CNFManager::Points::Results::RESULTS_DIR_ARG)
  MCP::Server.new(allow_install: allow_install, results_dir: results_dir).run
end
