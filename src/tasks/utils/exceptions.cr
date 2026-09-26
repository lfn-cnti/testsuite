# Documented exceptions (CBPP-0003): a finding a CNF declares it needs, with
# the reason, is reported as excepted instead of failed. The declaration
# lives in the common.exceptions section of cnti-testsuite.yaml; see
# CNTI_TESTSUITE_YAML_USAGE.md.
module Exceptions
  # The exception covering a finding of `test` on workload `resource`, in
  # `container` (nil for a pod-level finding), with `value` the capability or
  # sysctl in question (nil when the test has no values); nil when none does.
  def self.covering(config, test : String, resource : String, container : String?, value : String?)
    config.common.exceptions.find do |exception|
      next false unless exception.test == test
      next false if !exception.container.empty? && exception.container != container
      next false if !exception.resource.empty? && exception.resource != resource
      next false if !exception.allow.empty? && (value.nil? || !exception.allow.includes?(value))
      true
    end
  end

  # Records a finding as excepted when an exception covers it, as impacted
  # otherwise. Returns true when it was excepted.
  def self.judge(result, config, test : String, kind : String, name : String, namespace : String?,
                 container : String?, value : String?, finding : String) : Bool
    if (exception = covering(config, test, name, container, value))
      result.add_excepted(kind, name, namespace, container: container, finding: finding, reason: exception.reason)
      true
    else
      result.add_impacted_resource(kind, name, namespace, container: container, reason: finding)
      false
    end
  end
end
