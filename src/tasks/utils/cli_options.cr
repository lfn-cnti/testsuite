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
    # The retired spelling - a `key=value` key or a bare flag word - which is
    # recognized only to point at the replacement. Nil for options that never
    # had one.
    retired : String? = nil do
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
    Option.new("cnf-config", Kind::Value, "a cnf-testsuite.yml, or the directory holding one", value_label: "PATH", file: true, retired: "cnf-config"),
    Option.new("timeout", Kind::Value, "how long to wait for install and uninstall operations", value_label: "SECONDS", numeric: true, retired: "timeout"),
    Option.new("results-dir", Kind::Value, "where results files go (default: ./cnti/results, or $CNF_TESTSUITE_RESULTS_DIR)", value_label: "PATH", retired: "results-dir"),
    Option.new("kubeconfig", Kind::Value, "the kubeconfig to use (default: $KUBECONFIG)", value_label: "PATH", file: true),
    Option.new("skip", Kind::Multi, "skip a task within a suite; repeatable", value_label: "TASK", retired: "exclude"),
    Option.new("input-config", Kind::Value, "update_config: the cnf-testsuite.yml to convert", value_label: "PATH", file: true, retired: "input-config"),
    Option.new("output-config", Kind::Value, "update_config: where to write the converted file", value_label: "PATH", file: true, retired: "output-config"),
    Option.new("pod-labels", Kind::Value, "label selector of the pods a chaos test targets", value_label: "LABELS", retired: "pod-labels"),
    Option.new("strict", Kind::Flag, "stop at the first failed or errored test", retired: "strict"),
    Option.new("essential", Kind::Flag, "cert: run only the essential tests", retired: "essential"),
    Option.new("poc", Kind::Flag, "include proof-of-concept tests", retired: "poc"),
    Option.new("wip", Kind::Flag, "include work-in-progress tests", retired: "wip"),
    Option.new("alpha", Kind::Flag, "include alpha tests", retired: "alpha"),
    Option.new("beta", Kind::Flag, "include beta tests", retired: "beta"),
    Option.new("destructive", Kind::Flag, "allow destructive tests", retired: "destructive"),
    Option.new("skip-wait-for-install", Kind::Flag, "do not wait for resources to become ready after install", internal: "skip_wait_for_install", retired: "skip_wait_for_install"),
    Option.new("skip-wait-for-uninstall", Kind::Flag, "do not wait for resources to be removed after uninstall", internal: "skip_wait_for_uninstall", retired: "skip_wait_for_uninstall"),
  ]

  def self.[]?(name : String) : Option?
    ALL.find { |option| option.name == name }
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
    ALL.map(&.long)
  end

  # The option a retired `key=value` key or bare flag word stood for.
  def self.retired_named(name : String) : Option?
    ALL.find { |option| option.takes_value? && option.retired == name }
  end

  def self.retired_flag(word : String) : Option?
    ALL.find { |option| option.kind.flag? && option.retired == word }
  end
end
