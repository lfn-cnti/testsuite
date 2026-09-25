require "./utils.cr"


GENERIC_OPERATION_TIMEOUT = ENV.has_key?("CNTI_TESTSUITE_GENERIC_OPERATION_TIMEOUT") ? ENV["CNTI_TESTSUITE_GENERIC_OPERATION_TIMEOUT"].to_i : 60
RESOURCE_CREATION_TIMEOUT = ENV.has_key?("CNTI_TESTSUITE_RESOURCE_CREATION_TIMEOUT") ? ENV["CNTI_TESTSUITE_RESOURCE_CREATION_TIMEOUT"].to_i : 120
NODE_READINESS_TIMEOUT =    ENV.has_key?("CNTI_TESTSUITE_NODE_READINESS_TIMEOUT") ? ENV["CNTI_TESTSUITE_NODE_READINESS_TIMEOUT"].to_i :       240
# How long node_drain keeps a node cordoned after its workloads have
# recovered elsewhere, so that a recovery is not just a flap.
NODE_DRAIN_TOTAL_CHAOS_DURATION = ENV.has_key?("CNTI_TESTSUITE_NODE_DRAIN_TOTAL_CHAOS_DURATION") ? ENV["CNTI_TESTSUITE_NODE_DRAIN_TOTAL_CHAOS_DURATION"].to_i : 30
POD_READINESS_TIMEOUT =     ENV.has_key?("CNTI_TESTSUITE_POD_READINESS_TIMEOUT") ? ENV["CNTI_TESTSUITE_POD_READINESS_TIMEOUT"].to_i :         180
LITMUS_CHAOS_TEST_TIMEOUT = ENV.has_key?("CNTI_TESTSUITE_LITMUS_CHAOS_TEST_TIMEOUT") ? ENV["CNTI_TESTSUITE_LITMUS_CHAOS_TEST_TIMEOUT"].to_i : 1800
# How long cnf_install waits for an operator to create the first workload owned by the CNF's custom resources.
OWNED_RESOURCE_DISCOVERY_TIMEOUT = ENV.has_key?("CNTI_TESTSUITE_OWNED_RESOURCE_DISCOVERY_TIMEOUT") ? ENV["CNTI_TESTSUITE_OWNED_RESOURCE_DISCOVERY_TIMEOUT"].to_i : 60

def repeat_with_timeout(timeout, errormsg, reset_on_nil=false, delay=2, &block)
  start_time = Time.utc
  while (Time.utc - start_time).to_i < timeout
    result = yield
    if result.nil?
      if reset_on_nil
        start_time = Time.utc
      else
        raise "Unexpected nil result of executed block, check the return value or parameter 'reset_on_nil'"
      end
    elsif result
      return true
    end
    sleep(Time::Span.new(seconds: delay))
    Log.debug { "Time left: #{timeout - (Time.utc - start_time).to_i} seconds" }
  end
  Log.error { errormsg }
  false
end
