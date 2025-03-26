require "sam"
require "file_utils"
require "colorize"
require "totem"

desc "Sets up the CNF test suite, the K8s cluster, and upstream projects"

task "setup", ["version", "helm_local_install", "prereqs", "create_namespace", "configuration_file_setup", "install_apisnoop", "install_sonobuoy", "install_chart_testing", "cnf_testsuite_setup", "install_kind"] do  |_, args|
  stdout_success "Dependency installation complete"
end

task "create_namespace" do |_, args|
  ensure_kubeconfig!
  if KubectlClient::Apply.namespace(TESTSUITE_NAMESPACE)
    stdout_success "Created #{TESTSUITE_NAMESPACE} namespace on the Kubernetes cluster"
    cmd = "kubectl label namespace #{TESTSUITE_NAMESPACE} pod-security.kubernetes.io/enforce=privileged"
    ShellCmd.run(cmd, "Label.namespace")
  else
    stdout_failure "Could not create #{TESTSUITE_NAMESPACE} namespace on the Kubernetes cluster"
  end
rescue e : KubectlClient::ShellCMD::AlreadyExistsError
  stdout_success "#{TESTSUITE_NAMESPACE} namespace already exists on the Kubernetes cluster"
  cmd = "kubectl label --overwrite namespace #{TESTSUITE_NAMESPACE} pod-security.kubernetes.io/enforce=privileged"
  ShellCmd.run(cmd, "Label.namespace")
end

task "configuration_file_setup" do |_, args|
  Log.debug { "configuration_file_setup" }
  CNFManager::Points.create_points_yml
end

task "validate_config" do |_, args|
  if args.named["cnf-config"]?
    config = CNFInstall::Config.parse_cnf_config_from_file(args.named["cnf-config"].to_s)
    puts "Successfully validated CNF config"
    Log.info {"Config: #{config.inspect}"}
  else
    stdout_failure "cnf-config parameter needed"
    exit 1
  end
end
