require "./spec_helper"
require "colorize"
require "../src/tasks/utils/utils.cr"
require "file_utils"
require "sam"
require "socket"

# used in private repo/oci repo/cert test
def fetch_nginx_chart_tgz(dest_dir : String, version = "15.10.0") : String
  tgz = File.join(dest_dir, "nginx-#{version}.tgz")

  # Add repo (no-op if it already exists)
  ok = Helm.helm_repo_add("bitnami", "https://charts.bitnami.com/bitnami")
  ok.should be_true

  # Pull .tgz (no untar) into dest_dir
  resp = Helm.pull("bitnami", "nginx", version: version, destination: dest_dir, untar: false)
  resp[:status].success?.should be_true

  tgz
end

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

  it "'cnf_install/cnf_uninstall' should install/uninstall with cnf-path arg as an alias for cnf-config (.yml)", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=example-cnfs/coredns/cnf-testsuite.yml")
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      result = ShellCmd.cnf_uninstall()
      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
    end
  end

  it "'cnf_install/cnf_uninstall' should install/uninstall with cnf-path arg as an alias for cnf-config (.yaml)", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=spec/fixtures/cnf-testsuite.yaml")
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

  it "'cnf_install/cnf_uninstall' should fail on invalid config path", tags: ["cnf_installation"] do
    begin
      result = ShellCmd.cnf_install("cnf-path=spec/fixtures/bad-config-path", expect_failure: true)
      (/Invalid CNF configuration file: spec\/fixtures\/bad-config-path\./ =~ result[:output]).should_not be_nil
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
      (/All "coredns" resources are gone/ =~ result[:output]).should_not be_nil
      (/All "memcached" resources are gone/ =~ result[:output]).should_not be_nil
      (/All "nginx" resources are gone/ =~ result[:output]).should_not be_nil
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
      (/All "nginx" resources are gone/ =~ result[:output]).should_not be_nil
      (/All "redis" resources are gone/ =~ result[:output]).should_not be_nil
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
      (/All "nginx" resources are gone/ =~ result[:output]).should_not be_nil
      (/Skipping uninstallation of deployment "coredns": no manifest/ =~ result[:output]).should_not be_nil
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
      result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample-elk-stack/cnf-testsuite.yml", timeout: 600)
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

      (/All CNF deployments were uninstalled/ =~ result[:output]).should_not be_nil
  
      lines = result[:output].split('\n')
  
      uninstallation_order = [
        /All "kibana" resources are gone/,
        /All "logstash" resources are gone/,
        /All "elasticsearch" resources are gone/
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

  it "'cnf_uninstall' should fail for a stuck manifest deployment", tags: ["cnf_installation"] do
    result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample_stuck_finalizer/cnf-testsuite.yml")
    result[:status].success?.should be_true

    result = ShellCmd.cnf_uninstall(timeout: 30, expect_failure: true)
    (/Some resources of "stuck_finalizer" did not finish deleting within the timeout/ =~ result[:output]).should_not be_nil
  ensure
    # Patch out finalizer
    KubectlClient::Utils.patch(
      "pod",
      "stuck-pod",
      "cnfspace",
      "merge",
      "{\"metadata\":{\"finalizers\":[]}}",
    )
    result = ShellCmd.cnf_uninstall
    result[:status].success?.should be_true
    (/CNF uninstallation skipped/ =~ result[:output]).should_not be_nil
  end

  it "'cnf_uninstall' should fail for a stuck helm deployment", tags: ["cnf_installation"] do
    result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample_stuck_helm_deployment/")
    result[:status].success?.should be_true

    # Inject finalizer into Deployment pod template
    KubectlClient::Utils.patch(
      "pod",
      nil,
      "cnf-default",
      "merge",
      %({"metadata":{"finalizers":["example.com/stuck"]}}),
      { "app.kubernetes.io/instance" => "stuck-nginx" }
    )

    result = ShellCmd.cnf_uninstall(timeout: 30, expect_failure: true)
    (/Some resources of "stuck-nginx" did not finish deleting within the timeout/ =~ result[:output]).should_not be_nil
  ensure
    # Patch out finalizer
    KubectlClient::Utils.patch(
      "pod",
      nil,
      "cnf-default",
      "merge",
      "{\"metadata\":{\"finalizers\":[]}}",
      {"app.kubernetes.io/instance" => "stuck-nginx"}
    )

    result = ShellCmd.cnf_uninstall
    result[:status].success?.should be_true
    (/CNF uninstallation skipped/ =~ result[:output]).should_not be_nil
  end

  it "'cnf_install' should pass for oci repository", tags: ["cnf_installation"] do
    local_registry_port = 53123
    tgz = fetch_nginx_chart_tgz("sample-cnfs/sample_oci_repo")

    begin
      # Start registry
      DockerClient.run("rm -f oci-reg >/dev/null 2>&1 || true")
      DockerClient.run(
        "run -d --name oci-reg \
        -p #{local_registry_port}:5000 \
        -e REGISTRY_AUTH=htpasswd \
        -e REGISTRY_AUTH_HTPASSWD_REALM=\"Registry\" \
        -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
        registry:2"
      )[:status].success?.should be_true

      # Wait for port
      ok = repeat_with_timeout(15, "Local OCI registry didn't open port #{local_registry_port}", false, 1) do
        begin s = TCPSocket.new("127.0.0.1", local_registry_port); s.close; true rescue false end
      end
      ok.should be_true

      # Create htpasswd inside container
      DockerClient.run(
        "run --rm --entrypoint htpasswd httpd:2 -Bbn dummy secret \
        | docker exec -i oci-reg sh -lc 'mkdir -p /auth && cat > /auth/htpasswd'"
      )[:status].success?.should be_true

      # Push chart to the registry
      Helm.registry_login("localhost:#{local_registry_port}", username: "dummy", password: "secret", insecure: true).should be_true
      Helm.push_oci(tgz, "oci://localhost:#{local_registry_port}/helm", plain_http: true)

      # Logout before install
      ShellCmd.run("helm registry logout localhost:#{local_registry_port}")

      result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample_oci_repo/")
      result[:status].success?.should be_true
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      DockerClient.run("rm -f oci-reg >/dev/null 2>&1 || true")
      FileUtils.rm_rf(tgz) rescue nil

      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'cnf_install' should pass for private helm repository", tags: ["cnf_installation"] do
    chart_museum_port = 53124
    tgz = fetch_nginx_chart_tgz("sample-cnfs/sample_private_repo")

    begin
      # Start ChartMuseum with basic auth
      DockerClient.run("rm -f cm >/dev/null 2>&1 || true")
      DockerClient.run(
        "run -d --name cm \
        -p #{chart_museum_port}:8080 \
        -e STORAGE=local \
        -e STORAGE_LOCAL_ROOTDIR=/tmp/charts \
        -e BASIC_AUTH_USER=dummy \
        -e BASIC_AUTH_PASS=secret \
        chartmuseum/chartmuseum:latest"
      )[:status].success?.should be_true

      # Wait for port
      ok = repeat_with_timeout(15, "ChartMuseum didn't open port #{chart_museum_port}", false, 1) do
        begin s = TCPSocket.new("127.0.0.1", chart_museum_port); s.close; true rescue false end
      end
      ok.should be_true

      # HTTP health wait
      healthy = repeat_with_timeout(60, "ChartMuseum not healthy on /health", false, 1) do
        ShellCmd.run("curl -fsS http://localhost:#{chart_museum_port}/health")[:status].success?
      end
      healthy.should be_true

      # Upload chart to ChartMuseum
      upload = ShellCmd.run(%(curl -fsS -u dummy:secret --data-binary @#{tgz} http://localhost:#{chart_museum_port}/api/charts))
      upload[:status].success?.should be_true

      result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample_private_repo/")
      result[:status].success?.should be_true
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      DockerClient.run("rm -f cm >/dev/null 2>&1 || true")
      FileUtils.rm_rf(tgz) rescue nil

      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end

  it "'cnf_install' should require client cert for OCI registry (mTLS)", tags: ["cnf_installation"] do
    registry_port = 54125
    reg_host      = "127.0.0.1.nip.io"
    reg_host_port = "#{reg_host}:#{registry_port}"
    tgz = fetch_nginx_chart_tgz("sample-cnfs/sample_tls_repo")

    # TLS material
    tls_dir = "sample-cnfs/sample_tls_repo/tls"
    FileUtils.mkdir_p(tls_dir)
    ca_key  = "#{tls_dir}/ca.key"
    ca_crt  = "#{tls_dir}/ca.crt"
    srv_key = "#{tls_dir}/server.key"
    srv_csr = "#{tls_dir}/server.csr"
    srv_crt = "#{tls_dir}/server.crt"
    cli_key = "#{tls_dir}/client.key"
    cli_csr = "#{tls_dir}/client.csr"
    cli_crt = "#{tls_dir}/client.crt"

    # Snapshot proxies to restore later
    proxy_vars = %w[http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY]
    prev_proxy = {} of String => String?
    proxy_vars.each { |k| prev_proxy[k] = ENV[k]? }

    begin
      # Disable proxies for localhost
      proxy_vars.each { |k| ENV.delete(k) }
      ENV["NO_PROXY"] = "127.0.0.1,localhost,#{reg_host},.nip.io,::1"
      ENV["no_proxy"] = ENV["NO_PROXY"]

      # Create CA, server (SAN: localhost/127.0.0.1/reg_host), and client certs
      ShellCmd.run(%(openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=Test CA" -keyout #{ca_key} -out #{ca_crt}))[:status].success?.should be_true
      ShellCmd.run(%(openssl req -newkey rsa:2048 -nodes -subj "/CN=#{reg_host}" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,DNS:#{reg_host}" -keyout #{srv_key} -out #{srv_csr}))[:status].success?.should be_true
      ShellCmd.run(%(openssl x509 -req -in #{srv_csr} -CA #{ca_crt} -CAkey #{ca_key} -CAcreateserial -days 3650 -out #{srv_crt} -copy_extensions copy))[:status].success?.should be_true
      ShellCmd.run(%(openssl req -newkey rsa:2048 -nodes -subj "/CN=test-client" -keyout #{cli_key} -out #{cli_csr}))[:status].success?.should be_true
      ShellCmd.run(%(openssl x509 -req -in #{cli_csr} -CA #{ca_crt} -CAkey #{ca_key} -CAcreateserial -days 3650 -out #{cli_crt}))[:status].success?.should be_true

      [ca_crt, srv_crt, srv_key, cli_crt, cli_key].each { |p| File.exists?(p).should be_true }

      # Start registry (mTLS)
      config_path = "sample-cnfs/sample_tls_repo/config.yml"
      DockerClient.run("rm -f oci-reg-mtls >/dev/null 2>&1 || true")
      DockerClient.run(
        "run -d --name oci-reg-mtls " \
        "-p #{registry_port}:5000 " \
        "-v #{File.expand_path(tls_dir)}:/certs:ro " \
        "-v #{File.expand_path(config_path)}:/etc/docker/registry/config.yml:ro " \
        "registry:2"
      )[:status].success?.should be_true

      # Wait for port and TLS handshake (ignore HTTP code)
      ok = repeat_with_timeout(30, "mTLS registry didn't become ready", false, 1) do
        begin
          s = TCPSocket.new("127.0.0.1", registry_port); s.close
          ShellCmd.run(%(curl -sS --noproxy '*' -o /dev/null --cacert #{ca_crt} --cert #{cli_crt} --key #{cli_key} https://#{reg_host_port}/v2/))[:status].success?
        rescue
          false
        end
      end
      puts DockerClient.run("logs --tail=200 oci-reg-mtls")[:output].to_s unless ok
      ok.should be_true

      # Negative login (no client certs) must fail
      Helm.registry_login(reg_host_port, username: "dummy", password: "secret", insecure: false).should be_false

      # Positive login with TLS files
      Helm.registry_login(reg_host_port, username: "dummy", password: "secret", ca_file: ca_crt, cert_file: cli_crt, key_file: cli_key, insecure: false).should be_true

      # Push chart over HTTPS + mTLS
      Helm.push_oci(tgz, "oci://#{reg_host_port}/helm", plain_http: false, ca_file: ca_crt, cert_file: cli_crt, key_file: cli_key)
      ShellCmd.run("helm registry logout #{reg_host_port}")

      # Install via testsuite (pull requires mTLS)
      result = ShellCmd.cnf_install("cnf-path=sample-cnfs/sample_tls_repo/")
      result[:status].success?.should be_true
      (/CNF installation complete/ =~ result[:output]).should_not be_nil
    ensure
      DockerClient.run("rm -f oci-reg-mtls >/dev/null 2>&1 || true")
      FileUtils.rm_rf(tls_dir) rescue nil
      FileUtils.rm_rf(tgz) rescue nil
      prev_proxy.each { |k, v| v.try { |s| ENV[k] = s } || ENV.delete(k) }

      result = ShellCmd.cnf_uninstall
      result[:status].success?.should be_true
    end
  end
end
