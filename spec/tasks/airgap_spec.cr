require "../spec_helper"
require "../../src/tasks/airgap.cr"
require "file_utils"

describe "Airgap", tags: ["points"] do
  it "reads image references from a YAML stream" do
    yaml = <<-YAML
      apiVersion: apps/v1
      kind: Deployment
      spec:
        template:
          spec:
            containers:
              - name: app
                image: "ghcr.io/acme/app:v1"
              - name: sidecar
                image: 'docker.io/library/nginx:1.27'
            initContainers:
            - image: busybox:1.36
            # A trailing YAML comment is not part of the image reference.
            - image: ghcr.io/acme/comment:v1 # pinned release
      YAML

    Airgap.images_from_yaml(yaml).should eq([
      "ghcr.io/acme/app:v1",
      "docker.io/library/nginx:1.27",
      "busybox:1.36",
      "ghcr.io/acme/comment:v1",
    ])
  end

  it "reads container names with their images" do
    yaml = <<-YAML
      containers:
        - name: app
          image: ghcr.io/acme/app:v1
        - image: docker.io/library/nginx:1.27
          name: sidecar
    YAML

    Airgap.container_images_from_yaml(yaml).should eq([
      {name: "app", image: "ghcr.io/acme/app:v1"},
      {name: "sidecar", image: "docker.io/library/nginx:1.27"},
    ])
  end

  it "adds configured compatibility tags to the deployed repositories" do
    config = File.tempname("airgap-config", ".yaml")
    cnf_dir = File.tempname("airgap-cnf")
    begin
      File.write(config, <<-YAML)
      ---
      config_version: v2
      common:
        container_names:
        - name: app
          rolling_update_test_tag: "2.0"
          rolling_downgrade_test_tag: 1.0
          rolling_version_change_test_tag: v2
          rollback_from_tag: 1.0
      deployments:
        manifests:
        - name: app
          manifest_directory: manifests
      YAML
      Dir.mkdir_p(File.join(cnf_dir, "manifests"))
      File.write(File.join(cnf_dir, "manifests", "deployment.yaml"), <<-YAML)
      containers:
        - name: app
          image: registry:5000/acme/app:1.5
      YAML

      Airgap.compatibility_images(config, [cnf_dir]).should eq([
        "registry:5000/acme/app:1.0",
        "registry:5000/acme/app:2.0",
        "registry:5000/acme/app:v2",
      ])
    ensure
      FileUtils.rm_rf(config)
      FileUtils.rm_rf(cnf_dir)
    end
  end

  it "reads the Litmus runner image from the operator environment" do
    yaml = <<-YAML
      env:
        - name: CHAOS_RUNNER_IMAGE
          value: "litmuschaos.docker.scarf.sh/litmuschaos/chaos-runner:3.31.0"
      YAML

    Airgap.images_from_yaml(yaml).should eq([
      "litmuschaos.docker.scarf.sh/litmuschaos/chaos-runner:3.31.0",
    ])
  end

  it "uses local images in offline Litmus manifests" do
    path = File.tempname("airgap-litmus", ".yaml")
    previous = ENV["CNTI_TESTSUITE_OFFLINE"]?
    begin
      File.write(path, <<-YAML)
        containers:
          - image: litmuschaos/chaos-runner:v3
            imagePullPolicy: Always
          - image: litmuschaos/chaos-operator:v3
            imagePullPolicy: "Always"
      YAML

      ENV["CNTI_TESTSUITE_OFFLINE"] = "1"
      LitmusManager.use_local_images(path)

      File.read(path).should contain("imagePullPolicy: IfNotPresent")
      File.read(path).should_not contain("Always")
    ensure
      FileUtils.rm_rf(path)
      if previous
        ENV["CNTI_TESTSUITE_OFFLINE"] = previous
      else
        ENV.delete("CNTI_TESTSUITE_OFFLINE")
      end
    end
  end

  it "collects suite, operator, fault and CNF images once each" do
    operator = File.tempname("airgap-operator", ".yaml")
    cnf_dir = File.tempname("airgap-cnf")
    bundle = File.tempname("airgap-bundle")
    previous_dir = ENV["CNTI_TESTSUITE_OFFLINE_DIR"]?
    begin
      ENV["CNTI_TESTSUITE_OFFLINE_DIR"] = bundle

      File.write(operator, <<-YAML)
        containers:
          - image: litmuschaos/chaos-operator:v3
          - image: #{ClusterTools::IMAGE}
        YAML

      fault = Offline.cache_path(Airgap.fault_url("disk-fill"))
      FileUtils.mkdir_p(File.dirname(fault))
      File.write(fault, <<-YAML)
        containers:
          - image: litmuschaos/chaos-runner:v3
        YAML

      Dir.mkdir_p(File.join(cnf_dir, "manifests"))
      File.write(File.join(cnf_dir, "manifests", "deployment.yaml"), <<-YAML)
        containers:
          - image: ghcr.io/acme/app:v1
      YAML
      File.write(File.join(cnf_dir, "manifests", "service.yaml"), <<-YAML)
        spec:
          ports:
            - port: 80
      YAML

      images = Airgap.collect_images(operator, [cnf_dir])
      images.should eq([
        ClusterTools::IMAGE,
        "ghcr.io/acme/app:v1",
        "litmuschaos/chaos-operator:v3",
        "litmuschaos/chaos-runner:v3",
      ].sort)
    ensure
      FileUtils.rm_rf(operator)
      FileUtils.rm_rf(cnf_dir)
      FileUtils.rm_rf(bundle)
      if previous_dir
        ENV["CNTI_TESTSUITE_OFFLINE_DIR"] = previous_dir
      else
        ENV.delete("CNTI_TESTSUITE_OFFLINE_DIR")
      end
    end
  end

  it "lists the artifacts a bundle needs, including every Litmus fault" do
    artifacts = Airgap.host_artifacts
    artifacts.should contain(Setup::HELM_URL)
    artifacts.should contain(LitmusManager::LITMUS_OPERATOR)
    LitmusManager::FAULTS.each do |fault|
      artifacts.should contain(Airgap.fault_url(fault))
    end
  end

  it "uses the configured chaos-charts mirror for fault artifacts" do
    previous = ENV[LitmusManager::CHAOS_CHARTS_ENV]?
    begin
      ENV[LitmusManager::CHAOS_CHARTS_ENV] = "https://mirror.example/chaos-charts/"

      Airgap.fault_url("disk-fill").should eq(
        "https://mirror.example/chaos-charts/faults/kubernetes/disk-fill/fault.yaml")
    ensure
      if previous
        ENV[LitmusManager::CHAOS_CHARTS_ENV] = previous
      else
        ENV.delete(LitmusManager::CHAOS_CHARTS_ENV)
      end
    end
  end
end
