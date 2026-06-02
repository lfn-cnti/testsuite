require "./utils.cr"


GENERIC_OPERATION_TIMEOUT = ENV.has_key?("CNF_TESTSUITE_GENERIC_OPERATION_TIMEOUT") ? ENV["CNF_TESTSUITE_GENERIC_OPERATION_TIMEOUT"].to_i : 60
RESOURCE_CREATION_TIMEOUT = ENV.has_key?("CNF_TESTSUITE_RESOURCE_CREATION_TIMEOUT") ? ENV["CNF_TESTSUITE_RESOURCE_CREATION_TIMEOUT"].to_i : 120
NODE_READINESS_TIMEOUT =    ENV.has_key?("CNF_TESTSUITE_NODE_READINESS_TIMEOUT") ? ENV["CNF_TESTSUITE_NODE_READINESS_TIMEOUT"].to_i :       240
POD_READINESS_TIMEOUT =     ENV.has_key?("CNF_TESTSUITE_POD_READINESS_TIMEOUT") ? ENV["CNF_TESTSUITE_POD_READINESS_TIMEOUT"].to_i :         180
LITMUS_CHAOS_TEST_TIMEOUT = ENV.has_key?("CNF_TESTSUITE_LITMUS_CHAOS_TEST_TIMEOUT") ? ENV["CNF_TESTSUITE_LITMUS_CHAOS_TEST_TIMEOUT"].to_i : 1800

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
