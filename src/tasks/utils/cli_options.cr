# The one description of every option the CLI accepts. Validation, help and
# completion all read this list, so they cannot drift from each other or from
# what the tasks consume. Tasks keep reading `args.named[<name>]` and
# `args.raw.includes?(<internal name>)`; only the command-line spelling is
# decided here.
module CLIOptions
  enum Kind
    Value # --name VALUE
    Flag  # --name
    Multi # --name VALUE, repeatable
  end

  record Option,
    name : String,
    kind : Kind,
    description : String,
    value_label : String = "",
    # What tasks read: args.named key for values, the raw word for flags.
    internal : String = "",
    numeric : Bool = false,
    file : Bool = false,
    # Legacy spelling still accepted until the legacy forms are removed:
    # `key=value` for values, a bare word for flags. Nil for new options.
    legacy : String? = nil,
    # Accepted but not advertised.
    hidden : Bool = false do
    def long : String
      "--#{name}"
    end

    def internal_name : String
      internal.empty? ? name : internal
    end

    def takes_value? : Bool
      !kind.flag?
    end
  end

  ALL = [
    Option.new("cnf-config", Kind::Value, "a cnf-testsuite.yml, or the directory holding one", value_label: "PATH", file: true, legacy: "cnf-config"),
    Option.new("timeout", Kind::Value, "how long to wait for install and uninstall operations", value_label: "SECONDS", numeric: true, legacy: "timeout"),
    Option.new("results-dir", Kind::Value, "where results files go (default: ./cnti/results, or $CNF_TESTSUITE_RESULTS_DIR)", value_label: "PATH", legacy: "results-dir"),
    Option.new("kubeconfig", Kind::Value, "the kubeconfig to use (default: $KUBECONFIG)", value_label: "PATH", file: true),
    Option.new("skip", Kind::Multi, "skip a task within a suite; repeatable", value_label: "TASK"),
    Option.new("input-config", Kind::Value, "update_config: the cnf-testsuite.yml to convert", value_label: "PATH", file: true, legacy: "input-config"),
    Option.new("output-config", Kind::Value, "update_config: where to write the converted file", value_label: "PATH", file: true, legacy: "output-config"),
    Option.new("pod-labels", Kind::Value, "label selector of the pods a chaos test targets", value_label: "LABELS", legacy: "pod-labels"),
    Option.new("baseline-count", Kind::Value, "smf_upf_heartbeat: heartbeats to sample for the baseline", value_label: "N", numeric: true, legacy: "baseline-count"),
    Option.new("strict", Kind::Flag, "stop at the first failed or errored test", legacy: "strict"),
    Option.new("essential", Kind::Flag, "cert: run only the essential tests", legacy: "essential"),
    Option.new("poc", Kind::Flag, "include proof-of-concept tests", legacy: "poc"),
    Option.new("wip", Kind::Flag, "include work-in-progress tests", legacy: "wip"),
    Option.new("alpha", Kind::Flag, "include alpha tests", legacy: "alpha"),
    Option.new("beta", Kind::Flag, "include beta tests", legacy: "beta"),
    Option.new("destructive", Kind::Flag, "allow destructive tests", legacy: "destructive"),
    Option.new("skip-wait-for-install", Kind::Flag, "do not wait for resources to become ready after install", internal: "skip_wait_for_install", legacy: "skip_wait_for_install"),
    Option.new("skip-wait-for-uninstall", Kind::Flag, "do not wait for resources to be removed after uninstall", internal: "skip_wait_for_uninstall", legacy: "skip_wait_for_uninstall"),
    # cert's `exclude="a b"` is superseded by --skip; accepted in its legacy
    # spelling only, until the legacy forms are removed.
    Option.new("exclude", Kind::Value, "cert: tests to leave out", value_label: "TESTS", legacy: "exclude", hidden: true),
  ]

  def self.[]?(name : String) : Option?
    ALL.find { |option| option.name == name }
  end

  def self.visible : Array(Option)
    ALL.reject(&.hidden)
  end

  def self.values : Array(Option)
    ALL.select { |option| option.kind.value? }
  end

  def self.flags : Array(Option)
    ALL.select { |option| option.kind.flag? }
  end

  def self.multis : Array(Option)
    ALL.select { |option| option.kind.multi? }
  end

  def self.long_names : Array(String)
    ALL.reject(&.hidden).map(&.long)
  end

  # Legacy `key=value` keys and bare flag words, by their legacy spelling.
  def self.legacy_named(name : String) : Option?
    ALL.find { |option| option.takes_value? && option.legacy == name }
  end

  def self.legacy_flag(word : String) : Option?
    ALL.find { |option| option.kind.flag? && option.legacy == word }
  end
end
