require "../spec_helper"
require "colorize"
require "../../src/tasks/utils/utils.cr"
require "../../src/tasks/kind_setup.cr"
require "file_utils"
require "sam"

def setup_5g_network
  deployment_names = [
    "open5gs-amf", "open5gs-ausf", "open5gs-bsf", "open5gs-mongodb", "open5gs-nrf", "open5gs-nssf", 
    "open5gs-pcf", "open5gs-populate", "open5gs-smf", "open5gs-udm", "open5gs-udr", "open5gs-upf"
  ]

  # Run Helm install command for the 5G network
  helm_chart_path = "sample-cnfs/sample_srsran_ueauth_open5gs/open5gs"
  Helm.install("open5gs", helm_chart_path, namespace: "oran", create_namespace: true)

  deployment_names.each do |deployment_name|
    # Wait for each deployment to be ready
    ready = KubectlClient::Wait.resource_wait_for_install("deployment", deployment_name, namespace: "oran")
    if !ready
      stdout_failure "Could not set up the 5g network"
      return false
    end
  end

  stdout_success "Successfully setup open5gs"
  return true
end

describe "5g" do
  before_all do
    result = ShellCmd.run_testsuite("setup")
    result[:status].success?.should be_true
  end

  it "'oran_e2_connection' should pass if the ORAN enabled RAN connects to the RIC using the e2 standard", tags: ["oran"]  do
    # (kosstennbl) TODO: Test and specs for 'oran_e2_connection' should be redesigned. Check #2153 for more info. Spec was using sample_srsran_ueauth_open5gs and sample-oran-ric.
  end

  it "'oran_e2_connection' should fail if the ORAN enabled RAN does not connect to the RIC using the e2 standard", tags: ["oran"]  do
    # (kosstennbl) TODO: Test and specs for 'oran_e2_connection' should be redesigned. Check #2153 for more info. Spec was using sample_srsran_ueauth_open5gs and sample-oran-noric.
  end

end
