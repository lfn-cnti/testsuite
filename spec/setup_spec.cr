require "./spec_helper"
require "colorize"
require "../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"

describe "Installation" do
  it "'setup' should install all cnf-testsuite dependencies before installing cnfs", tags: ["cnf_installation"]  do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
    (/Dependency installation complete/ =~ result[:output]).should_not be_nil
  end

  it "'uninstall_all' should uninstall CNF and testsuite dependencies", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-minimal-cnf/")
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.run_testsuite("uninstall_all")
      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
      (/Testsuite helper tools uninstalled./ =~ result[:output]).should_not be_nil
    end
  end

  it "'cnf_install' should pass with a minimal cnf-testsuite.yml", tags: ["cnf_installation"] do
    result = ShellCmd.cnf_install("cnf-path=./sample-cnfs/sample-minimal-cnf/")
    (/CNF installation complete/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
    (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
  end

  it "'cnf_install/cnf_uninstall' should install/uninstall with cnf-config arg as an alias for cnf-path", tags: ["cnf_installation"] do
    result = ShellCmd.cnf_install("cnf-config=./sample-cnfs/sample-minimal-cnf/")
    (/CNF installation complete/ =~ result[:output]).should_not be_nil
  ensure
    result = ShellCmd.cnf_uninstall()
    (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
  end

  it "'cnf_install/cnf_uninstall' should install/uninstall with cnf-path arg as an alias for cnf-config", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=example-cnfs/coredns/cnf-testsuite.yml")
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
    end
  end

  it "'cnf_install/cnf_uninstall' should fail on incorrect config", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=spec/fixtures/sample-bad-config.yml", expect_failure: true)
      (/Error during parsing CNF config/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
    end
  end

  it "'cnf_install/cnf_uninstall' should install/uninstall a cnf with a cnf-testsuite.yml", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-config=example-cnfs/coredns/cnf-testsuite.yml")
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
    end
  end

  it "'cnf_install/cnf_uninstall' should work with cnf-testsuite.yml that has no directory associated with it", tags: ["cnf_installation"] do
    begin
      #TODO force cnfs/<name> to be deployment name and not the directory name
      result = ShellCmd.cnf_install("cnf-config=spec/fixtures/cnf-testsuite.yml")
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
    end
  end

  it "'cnf_install/cnf_uninstall' should install/uninstall with helm_directory that descends multiple directories", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=sample-cnfs/multi_helm_directories/cnf-testsuite.yml")
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
    end
  end

  it "'cnf_install/cnf_uninstall' should properly install/uninstall old versions of cnf configs", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=spec/fixtures/cnf-testsuite-v1-example.yml")
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
    end
  end

  it "'cnf_install' should fail if another CNF is already installed", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample_coredns/cnf-testsuite.yml")
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
      result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample-minimal-cnf/cnf-testsuite.yml")
      (/A CNF is already installed. Installation of multiple CNFs is not allowed./ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
    end
  end

  it "'cnf_install/cnf_uninstall' should install/uninstall a cnf with multiple deployments", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample_multiple_deployments/cnf-testsuite.yml")
      (/All "coredns" deployment resources are up/ =~ result[:output]).should_not be_nil
      (/All "memcached" deployment resources are up/ =~ result[:output]).should_not be_nil
      (/All "nginx" deployment resources are up/ =~ result[:output]).should_not be_nil
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      (/Successfully uninstalled helm deployment "coredns"/ =~ result[:output]).should_not be_nil
      (/Successfully uninstalled helm deployment "memcached"/ =~ result[:output]).should_not be_nil
      (/Successfully uninstalled helm deployment "nginx"/ =~ result[:output]).should_not be_nil
      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
    end
  end

  it "'cnf_install/cnf_uninstall' should install/uninstall deployment with mixed installation methods", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample-nginx-redis/cnf-testsuite.yml")
      (/All "nginx" deployment resources are up/ =~ result[:output]).should_not be_nil
      (/All "redis" deployment resources are up/ =~ result[:output]).should_not be_nil
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      (/Successfully uninstalled helm deployment "nginx"/ =~ result[:output]).should_not be_nil
      (/Successfully uninstalled manifest deployment "redis"/ =~ result[:output]).should_not be_nil
      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
    end
  end

  it "'cnf_install/cnf_uninstall' should handle partial deployment failures gracefully", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample-partial-deployment-failure/cnf-testsuite.yml", expect_failure: true)
      (/All "nginx" deployment resources are up/ =~ result[:output]).should_not be_nil
      (/Deployment of "coredns" failed during CNF installation/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      (/Successfully uninstalled helm deployment "nginx"/ =~ result[:output]).should_not be_nil
    end
  end

  it "'cnf_install' should detect and report conflicts between deployments", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=spec/fixtures/sample-conflicting-deployments.yml", expect_failure: true)
      (/Deployment names should be unique/ =~ result[:output]).should_not be_nil
    ensure
      ShellCmd.cnf_uninstall()
    end
  end

  it "'cnf_install' should correctly handle deployment priority", tags: ["cnf_installation"] do
    # (kosstennbl) ELK stack requires to be installed with specific order, otherwise it would give errors
    begin
      result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample-elk-stack/cnf-testsuite.yml timeout=600")
      result[:status].success?.should be_true
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
  
      lines = result[:output].split('\n')
  
      installation_order = [
        /All "elasticsearch" deployment resources are up/,
        /All "logstash" deployment resources are up/,
        /All "kibana" deployment resources are up/
      ]
  
      # Find line indices for each installation regex
      install_line_indices = installation_order.map do |regex|
        idx = lines.index { |line| regex =~ line }
        idx.should_not be_nil
        idx.not_nil!  # Ensures idx is Int32, not Int32|Nil
      end
  
      # Verify installation order
      install_line_indices.each_cons(2) do |pair|
        pair[1].should be > pair[0]
      end
    ensure
      result = ShellCmd.cnf_uninstall()
      result[:status].success?.should be_true
      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
  
      lines = result[:output].split('\n')
  
      uninstallation_order = [
        /Successfully uninstalled helm deployment "kibana"/,
        /Successfully uninstalled helm deployment "logstash"/,
        /Successfully uninstalled helm deployment "elasticsearch"/
      ]
  
      # Find line indices for each uninstallation regex
      uninstall_line_indices = uninstallation_order.map do |regex|
        idx = lines.index { |line| regex =~ line }
        idx.should_not be_nil
        idx.not_nil!
      end
  
      # Verify uninstallation order
      uninstall_line_indices.each_cons(2) do |pair|
        pair[1].should be > pair[0]
      end
    end
  end

  it "'cnf_uninstall' should warn user if no CNF is found", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_uninstall()
      (/CNF uninstallation skipped/ =~ result[:output]).should_not be_nil
    end
  end
end
