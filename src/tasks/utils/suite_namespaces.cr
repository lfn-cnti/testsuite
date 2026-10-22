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

  # The cluster refused the privileged label: an admission webhook (Rancher's
  # lets only users with the updatepsa verb change Pod Security labels), a
  # policy. The message says what was refused, by what, and what to do (#2823).
  class LabelRefused < Exception
    def initialize(namespace : String, reason : String)
      super("Pod Security: the suite could not set #{ENFORCE}=privileged on namespace #{namespace}: #{reason}. " +
            "The suite's helper pods (privileged, hostPID) and the CNF need the privileged level there. " +
            "Have a user allowed to change Pod Security labels set #{ENFORCE}=privileged on #{TESTSUITE_NAMESPACE}, " +
            "the CNF's namespaces and litmus before the run, or run the suite as that user.")
    end
  end

  # Makes sure the namespace exists, with Pod Security level privileged. A
  # namespace that already enforces privileged is left alone, whoever created
  # it: no label write, so a namespace an administrator labelled beforehand
  # never meets a webhook that would refuse the change.
  def self.ensure_exists(namespace : String)
    existing = get(namespace)
    saved_here = false
    if existing.nil?
      KubectlClient::Apply.namespace(namespace, labels: MANAGED_BY)
    else
      level = existing.dig?("metadata", "labels", ENFORCE).try(&.as_s?)
      return if level == "privileged"
      # A second install finds privileged already set: what it replaced was
      # saved by the first.
      if !owned?(existing) && existing.dig?("metadata", "annotations", PREVIOUS_ENFORCE).nil?
        KubectlClient::Utils.annotate("namespace", namespace, ["#{PREVIOUS_ENFORCE}=#{level || NO_LEVEL}"])
        saved_here = true
      end
    end
    begin
      KubectlClient::Utils.label("namespace", namespace, ["#{ENFORCE}=privileged"])
    rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
      # The level was not replaced, so there is nothing for release to put
      # back: a saved level left here would undo a privileged label an
      # administrator sets after reading the message below.
      forget_saved_level(namespace) if saved_here && !privileged_now?(namespace)
      # kubectl's own line, past the exception's prefix and past any warning.
      lines = ex.message.to_s.sub(/\A.*?error: /m, "").lines.map(&.strip).reject(&.empty?)
      reason = lines.find { |l| !l.starts_with?("Warning:") } || lines.first.to_s
      raise LabelRefused.new(namespace, reason.sub(/\Aerror: /, ""))
    end
  end

  # Whether the namespace enforces privileged now, read again after a failed
  # write: a write the API server applied before kubectl reported an error
  # keeps its saved level for release. A read that fails counts as yes.
  private def self.privileged_now?(namespace : String) : Bool
    KubectlClient::Get.resource("namespace", namespace).dig?("metadata", "labels", ENFORCE).try(&.as_s?) == "privileged"
  rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
    true
  end

  private def self.forget_saved_level(namespace : String)
    KubectlClient::Utils.annotate("namespace", namespace, ["#{PREVIOUS_ENFORCE}-"])
  rescue ex : KubectlClient::ShellCMD::K8sClientCMDException
    Log.for("SuiteNamespaces.ensure_exists").warn { "Could not remove #{PREVIOUS_ENFORCE} from namespace #{namespace}: #{ex.message}" }
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
