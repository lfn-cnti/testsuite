require "../spec_helper"
require "file_utils"

describe "Offline", tags: ["points"] do
  it "recognises the offline switches" do
    previous = ENV["CNTI_TESTSUITE_OFFLINE"]?
    begin
      {"1", "true", "yes", "on", "ON"}.each do |value|
        ENV["CNTI_TESTSUITE_OFFLINE"] = value
        Offline.enabled?.should be_true
      end
      {"0", "false", "no", "off", ""}.each do |value|
        ENV["CNTI_TESTSUITE_OFFLINE"] = value
        Offline.enabled?.should be_false
      end
      ENV.delete("CNTI_TESTSUITE_OFFLINE")
      Offline.enabled?.should be_false
    ensure
      if previous
        ENV["CNTI_TESTSUITE_OFFLINE"] = previous
      else
        ENV.delete("CNTI_TESTSUITE_OFFLINE")
      end
    end
  end

  it "names a bundle file after the URL so two URLs cannot collide" do
    first = Offline.cache_path("https://example.test/releases/app.tar.gz")
    second = Offline.cache_path("https://example.test/other/app.tar.gz")

    File.basename(first).should end_with("-app.tar.gz")
    File.basename(second).should end_with("-app.tar.gz")
    first.should_not eq(second)
    Offline.cache_path("https://example.test/releases/app.tar.gz").should eq(first)
  end

  it "stores and resolves an artifact from the bundle" do
    bundle = File.tempname("offline-bundle")
    previous_dir = ENV["CNTI_TESTSUITE_OFFLINE_DIR"]?
    previous_mode = ENV["CNTI_TESTSUITE_OFFLINE"]?
    begin
      ENV["CNTI_TESTSUITE_OFFLINE_DIR"] = bundle
      ENV["CNTI_TESTSUITE_OFFLINE"] = "true"

      source = File.tempname("offline-source")
      File.write(source, "artifact body")
      url = "https://example.test/artifact.tar.gz"

      FileUtils.mkdir_p(File.dirname(Offline.cache_path(url)))
      File.write(Offline.cache_path(url), "")
      Offline.cached?(url).should be_false

      Offline.store(url, source)
      Offline.cached?(url).should be_true
      File.read(Offline.cache_path(url)).should eq("artifact body")

      output = File.tempname("offline-output")
      Offline.fetch_cached(url, output).should be_true
      File.read(output).should eq("artifact body")
    ensure
      if previous_dir
        ENV["CNTI_TESTSUITE_OFFLINE_DIR"] = previous_dir
      else
        ENV.delete("CNTI_TESTSUITE_OFFLINE_DIR")
      end
      if previous_mode
        ENV["CNTI_TESTSUITE_OFFLINE"] = previous_mode
      else
        ENV.delete("CNTI_TESTSUITE_OFFLINE")
      end
      FileUtils.rm_rf(bundle)
    end
  end

  it "keeps credentials out of missing-artifact diagnostics" do
    bundle = File.tempname("offline-bundle")
    previous_dir = ENV["CNTI_TESTSUITE_OFFLINE_DIR"]?
    previous_mode = ENV["CNTI_TESTSUITE_OFFLINE"]?
    begin
      ENV["CNTI_TESTSUITE_OFFLINE_DIR"] = bundle
      ENV["CNTI_TESTSUITE_OFFLINE"] = "true"

      url = "https://user:secret@mirror.example/charts/fault.yaml"
      error = expect_raises(Offline::MissingArtifactError) do
        Offline.fetch_cached(url, File.tempname("offline-output"))
      end

      message = error.message.to_s
      message.should contain("https://mirror.example/charts/fault.yaml")
      message.should_not contain("secret")
      message.should_not contain("user")
    ensure
      if previous_dir
        ENV["CNTI_TESTSUITE_OFFLINE_DIR"] = previous_dir
      else
        ENV.delete("CNTI_TESTSUITE_OFFLINE_DIR")
      end
      if previous_mode
        ENV["CNTI_TESTSUITE_OFFLINE"] = previous_mode
      else
        ENV.delete("CNTI_TESTSUITE_OFFLINE")
      end
      FileUtils.rm_rf(bundle)
    end
  end

  it "download_file reads the bundle instead of the network" do
    bundle = File.tempname("offline-bundle")
    previous_dir = ENV["CNTI_TESTSUITE_OFFLINE_DIR"]?
    previous_mode = ENV["CNTI_TESTSUITE_OFFLINE"]?
    begin
      ENV["CNTI_TESTSUITE_OFFLINE_DIR"] = bundle
      ENV["CNTI_TESTSUITE_OFFLINE"] = "true"

      url = "http://offline.invalid/never-reached.tar.gz"
      output = File.tempname("offline-download")

      expect_raises(Offline::MissingArtifactError) do
        download_file(url, output)
      end

      source = File.tempname("offline-source")
      File.write(source, "cached body")
      Offline.store(url, source)

      download_file(url, output).should be_true
      File.read(output).should eq("cached body")
    ensure
      if previous_dir
        ENV["CNTI_TESTSUITE_OFFLINE_DIR"] = previous_dir
      else
        ENV.delete("CNTI_TESTSUITE_OFFLINE_DIR")
      end
      if previous_mode
        ENV["CNTI_TESTSUITE_OFFLINE"] = previous_mode
      else
        ENV.delete("CNTI_TESTSUITE_OFFLINE")
      end
      FileUtils.rm_rf(bundle)
    end
  end
end
