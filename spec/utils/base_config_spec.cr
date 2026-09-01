require "../spec_helper"

describe "config.yml resolution" do
  it "resolves from the CWD first, then the suite home", tags: ["points"] do
    home = File.tempname("cfg-home")
    cwd = File.tempname("cfg-cwd")
    FileUtils.mkdir_p(home)
    FileUtils.mkdir_p(cwd)
    ENV["CNTI_TESTSUITE_DIR"] = home
    File.write(File.join(home, "config.yml"),
      {"toggles" => [{"name" => "wip", "toggle_on" => true}]}.to_yaml)

    Dir.cd(cwd) do
      base_config_path.should eq(File.join(home, "config.yml"))
      toggle("wip").should be_true

      # A project-local config overrides the home one.
      File.write("config.yml", {"toggles" => [{"name" => "wip", "toggle_on" => false}]}.to_yaml)
      base_config_path.should eq("config.yml")
      toggle("wip").should be_false

      File.delete("config.yml")
      File.delete(File.join(home, "config.yml"))
      base_config_path.should be_nil
    end
  ensure
    ENV.delete("CNTI_TESTSUITE_DIR")
    FileUtils.rm_rf(home.not_nil!)
    FileUtils.rm_rf(cwd.not_nil!)
  end
end
