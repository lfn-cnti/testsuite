require "json"

# Judging a CNF's pods against the Pod Security Standards with the API server
# itself: each pod's spec is created with --dry-run=server in a namespace the
# suite owns, labelled to enforce the level, so Pod Security Admission returns
# a verdict for exactly that pod, with the field and container. Nothing is
# created. The decisions are pure functions here so they can be unit-tested;
# the task in security.cr only lists the pods and runs kubectl.
module PodSecurity
  BASELINE_NAMESPACE = "cnti-pss-baseline"
  LEVEL              = "baseline"

  # What admission would check against the dry run's namespace rather than the
  # CNF's: the service account (and its token volume) and the priority, which
  # admission derives from the priority class again. Pod Security does not
  # judge them. Name, labels and annotations stay: baseline still reads the
  # AppArmor annotations. Ephemeral containers cannot be set on create; they
  # come from `kubectl debug`, not from the CNF.
  SPEC_FIELDS_DROPPED = ["nodeName", "serviceAccountName", "serviceAccount", "priority", "ephemeralContainers"]
  TOKEN_VOLUME_PREFIX = "kube-api-access-"

  # The pod as it is sent to the dry run.
  def self.dry_run_pod(pod : JSON::Any) : JSON::Any
    metadata = {} of String => JSON::Any
    if name = pod.dig?("metadata", "name")
      metadata["name"] = name
    end
    ["labels", "annotations"].each do |key|
      if value = pod.dig?("metadata", key)
        metadata[key] = value
      end
    end

    spec = (pod.dig?("spec").try(&.as_h?) || {} of String => JSON::Any).dup
    SPEC_FIELDS_DROPPED.each { |field| spec.delete(field) }
    token_volumes = [] of String
    if volumes = spec["volumes"]?.try(&.as_a?)
      kept = volumes.reject do |v|
        name = v.dig?("name").try(&.as_s?) || ""
        token = name.starts_with?(TOKEN_VOLUME_PREFIX) && v.dig?("projected")
        token_volumes << name if token
        token
      end
      spec["volumes"] = JSON::Any.new(kept)
    end
    ["containers", "initContainers"].each do |list|
      next unless containers = spec[list]?.try(&.as_a?)
      spec[list] = JSON::Any.new(containers.map { |c| without_mounts(c, token_volumes) })
    end

    JSON::Any.new({
      "apiVersion" => JSON::Any.new("v1"),
      "kind"       => JSON::Any.new("Pod"),
      "metadata"   => JSON::Any.new(metadata),
      "spec"       => JSON::Any.new(spec),
    })
  end

  private def self.without_mounts(container : JSON::Any, volumes : Array(String)) : JSON::Any
    c = container.as_h?.try(&.dup) || return container
    if mounts = c["volumeMounts"]?.try(&.as_a?)
      c["volumeMounts"] = JSON::Any.new(mounts.reject { |m| volumes.includes?(m.dig?("name").try(&.as_s?) || "") })
    end
    JSON::Any.new(c)
  end

  # The pod's controller, as "Kind/name", or the pod itself when it has none.
  def self.owner(pod : JSON::Any) : String
    refs = pod.dig?("metadata", "ownerReferences").try(&.as_a?) || [] of JSON::Any
    if ref = refs.find { |r| r.dig?("controller").try(&.as_bool?) == true }
      "#{ref.dig?("kind").try(&.as_s?)}/#{ref.dig?("name").try(&.as_s?)}"
    else
      "Pod/#{pod.dig?("metadata", "name").try(&.as_s?)}"
    end
  end

  # Pods of one owner with the same spec and annotations get the same verdict,
  # so one of them is judged; pods that differ (mid-rollout, or under an
  # operator) are each judged.
  def self.variant_key(pod : JSON::Any) : String
    sent = dry_run_pod(pod)
    "#{owner(pod)}|#{sent.dig?("metadata", "annotations").to_json}|#{sent["spec"].to_json}"
  end

  enum Verdict
    Passed
    Violation
    NotJudged
  end

  # The verdict of one dry run, from kubectl's exit status and output. Only
  # Pod Security's rejection is a violation; anything else that rejects the dry
  # run (a validating webhook, quota, the service account) leaves the pod not
  # judged, with the reason.
  def self.verdict(success : Bool, output : String) : {Verdict, String?}
    return {Verdict::Passed, nil} if success
    if m = output.match(/violates PodSecurity "#{LEVEL}:[^"]*": (.+)/)
      {Verdict::Violation, m[1].strip}
    else
      reason = output.lines.map(&.strip).find(&.presence) || "the dry run failed without a message"
      {Verdict::NotJudged, reason.sub(/^Error from server( \([A-Za-z]+\))?: /, "")}
    end
  end

  # Make sure the dry-run namespace exists and enforces the level. The API
  # server creates the namespace's default service account asynchronously, and
  # admission rejects a pod whose service account does not exist yet, so wait
  # for it.
  def self.ensure_namespace
    KubectlClient::Apply.namespace(BASELINE_NAMESPACE)
    KubectlClient::Utils.label("namespace", BASELINE_NAMESPACE,
      ["pod-security.kubernetes.io/enforce=#{LEVEL}", "pod-security.kubernetes.io/enforce-version=latest"])
    10.times do
      result = KubectlClient::ShellCMD.run("kubectl get serviceaccount default -n #{BASELINE_NAMESPACE}", Log.for("pod_security"))
      break if result[:status].success?
      sleep 1.second
    end
  end

  def self.uninstall_namespace
    KubectlClient::ShellCMD.run("kubectl delete namespace #{BASELINE_NAMESPACE} --ignore-not-found --wait=false", Log.for("pod_security"))
  end

  # One dry run: the pod's spec created in the baseline namespace, nothing
  # persisted. Input on stdin, no shell.
  def self.dry_run(pod : JSON::Any) : {Bool, String}
    output = IO::Memory.new
    status = Process.run("kubectl", ["create", "--dry-run=server", "-n", BASELINE_NAMESPACE, "-f", "-"],
      input: IO::Memory.new(dry_run_pod(pod).to_json), output: output, error: output)
    {status.success?, output.to_s}
  end
end
