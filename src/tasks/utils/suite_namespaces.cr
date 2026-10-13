# The namespaces the suite installs into, and what it leaves behind (#2213).
# A namespace the suite creates carries MANAGED_BY and is deleted when the
# suite removes what it installed there. A namespace that already existed is
# reused and kept; the suite only raises its Pod Security level to
# privileged, saving the level it had in PREVIOUS_ENFORCE, and puts that level
# back on release.
module SuiteNamespaces
  MANAGED_BY       = {"app.kubernetes.io/managed-by" => "cnti-testsuite"}
  ENFORCE          = "pod-security.kubernetes.io/enforce"
  PREVIOUS_ENFORCE = "cnti-testsuite/previous-pod-security-enforce"
  # Saved when the namespace had no enforce label, so release removes it.
  NO_LEVEL = "none"

  # Makes sure the namespace exists, with Pod Security level privileged.
  def self.ensure_exists(namespace : String)
    existing = get(namespace)
    if existing.nil?
      KubectlClient::Apply.namespace(namespace, labels: MANAGED_BY)
    elsif !owned?(existing)
      level = existing.dig?("metadata", "labels", ENFORCE).try(&.as_s?)
      saved = existing.dig?("metadata", "annotations", PREVIOUS_ENFORCE)
      # A second install finds privileged already set: what it replaced was
      # saved by the first.
      if saved.nil? && level != "privileged"
        KubectlClient::Utils.annotate("namespace", namespace, ["#{PREVIOUS_ENFORCE}=#{level || NO_LEVEL}"])
      end
    end
    KubectlClient::Utils.label("namespace", namespace, ["#{ENFORCE}=privileged"])
  end

  # Creates the namespace, as ensure_exists does, only if it doesn't exist; an
  # existing one is left as it is.
  def self.create_missing(namespace : String)
    ensure_exists(namespace) if get(namespace).nil?
  end

  # Deletes the namespace if the suite created it; otherwise puts back the Pod
  # Security level the suite replaced. Failures are logged, not raised: the
  # workloads are already gone.
  def self.release(namespace : String, wait : Bool = true)
    logger = Log.for("SuiteNamespaces.release")
    existing = get(namespace)
    return if existing.nil?

    if owned?(existing)
      logger.info { "Deleting namespace #{namespace}, created by the suite" }
      KubectlClient::Delete.resource("namespace", namespace,
        extra_opts: "--wait=#{wait} --timeout=#{GENERIC_OPERATION_TIMEOUT}s")
    elsif saved = existing.dig?("metadata", "annotations", PREVIOUS_ENFORCE).try(&.as_s?)
      logger.info { "Keeping namespace #{namespace}, which existed before; restoring its Pod Security level (#{saved})" }
      KubectlClient::Utils.label("namespace", namespace, [saved == NO_LEVEL ? "#{ENFORCE}-" : "#{ENFORCE}=#{saved}"])
      KubectlClient::Utils.annotate("namespace", namespace, ["#{PREVIOUS_ENFORCE}-"])
    end
  rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
    Log.for("SuiteNamespaces.release").warn { "Could not release namespace #{namespace}: #{ex.message}" }
  end

  def self.owned?(namespace_json : JSON::Any) : Bool
    MANAGED_BY.all? { |key, value| namespace_json.dig?("metadata", "labels", key).try(&.as_s?) == value }
  end

  private def self.get(namespace : String) : JSON::Any?
    KubectlClient::Get.resource("namespace", namespace)
  rescue KubectlClient::ShellCMD::NotFoundError
    nil
  end
end
