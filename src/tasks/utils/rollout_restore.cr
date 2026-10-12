# Puts the workloads a version-change test changed back to the images they
# were deployed with, so each test starts from the CNF as deployed and a
# rollout that fails stays a finding of the test that found it, instead of
# leaving a half rolled out CNF to every test after it (#2783).
module RolloutRestore
  # {kind, name, namespace} => {container => deployed image}
  alias Changed = Hash(Tuple(String, String, String), Hash(String, String))

  # Restores every changed workload and waits for it to be ready again.
  # A workload that does not come back is reported, with the reason, as an
  # impacted resource of the test; returns whether all came back.
  def self.restore(changed : Changed, result, test_name : String) : Bool
    all_back = true
    changed.each do |(kind, name, namespace), images|
      back = false
      begin
        images.each do |container, image|
          KubectlClient::Utils.set_image(kind, name, container, image, namespace: namespace)
        end
        back = complete?(kind, name, namespace)
        # A StatefulSet does not replace a pod that never became Ready when
        # its template is reverted: the pod has to be deleted, the forced
        # rollback in the Kubernetes documentation. Its controller then
        # recreates it from the deployed template.
        if !back && kind.downcase == "statefulset"
          delete_unready_pods(kind, name, namespace)
          back = complete?(kind, name, namespace)
        end
        unless back
          why = WorkloadDiagnostics.report(result, kind, name, namespace, "#{kind}/#{name} after restoring its deployed image")
          result.add_impacted_resource(kind, name, namespace,
            reason: "not back on its deployed image within #{POD_READINESS_TIMEOUT}s after #{test_name}#{why.first?.try { |w| ": #{w}" }}")
        end
      rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
        result.add_impacted_resource(kind, name, namespace,
          reason: "could not restore its deployed image after #{test_name}: #{ex.message.to_s.lines.first?}")
      end
      all_back &&= back
      RunStop.done(stop_key(kind, name, namespace))
    end
    all_back
  end

  def self.stop_key(kind : String, name : String, namespace : String) : String
    "restore the deployed images of #{kind}/#{name} in #{namespace}"
  end

  # What a stop runs while a workload is on a test image: the template goes
  # back to the deployed images, without waiting for the rollout.
  def self.set_back(kind : String, name : String, namespace : String, images : Hash(String, String)) : Nil
    images.each do |container, image|
      KubectlClient::Utils.set_image(kind, name, container, image, namespace: namespace)
    end
    nil
  end

  def self.complete?(kind : String, name : String, namespace : String) : Bool
    KubectlClient::Rollout.status(kind, name, namespace: namespace, timeout: "#{POD_READINESS_TIMEOUT}s")
    true
  rescue KubectlClient::ShellCMD::K8sClientCMDException
    false
  end

  def self.delete_unready_pods(kind : String, name : String, namespace : String)
    resource = KubectlClient::Get.resource(kind, name, namespace)
    KubectlClient::Get.pods_by_resource_labels(resource, namespace).each do |pod|
      next if WorkloadDiagnostics.pod_ready?(pod)
      pod_name = pod.dig("metadata", "name").as_s
      Log.for("RolloutRestore").info { "#{kind}/#{name}: deleting #{pod_name}, which did not become Ready, so it is recreated from the deployed template" }
      KubectlClient::Delete.resource("pod", pod_name, namespace)
    end
  end
end
