require "../spec_helper"

# A run must only ever touch the cnti/ workspace in the working directory;
# every other runtime artifact lives with the tools.
describe "Runtime artifact locations" do
  it "keeps runtime artifacts out of the working directory", tags: ["points"] do
    [
      LitmusManager.downloaded_operator_file,
      LitmusManager.modified_operator_file,
      Setup::CLUSTER_TOOLS_MANIFEST,
      Setup::RENDERED_MANIFESTS_DIR,
      Kubescape::RESULTS_FILE,
      Kubescape.control_results_file("C-0001"),
    ].each do |path|
      path.should start_with(tools_path)
      Path[path].absolute?.should be_true
    end
  end
end
