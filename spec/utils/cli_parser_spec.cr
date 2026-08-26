require "../spec_helper"
require "../../src/tasks/**"
require "../../src/tasks/utils/cli_args_validation"

# In-process: the parser maps a command line onto task paths and the Sam::Args
# the tasks read, without running anything.
private def parse(*tokens)
  CLIParser.parse!(tokens.to_a)
end

private def usage_error(*tokens) : Array(String)
  CLIParser.parse!(tokens.to_a)
  fail "expected a usage error for #{tokens.inspect}"
rescue e : CLIParser::UsageError
  e.errors
end

describe "CLI parser" do
  it "maps GNU-style options onto the arguments tasks read", tags: ["points"] do
    segments = parse("cnf_install", "--cnf-config", "x.yml", "--timeout=30", "--skip-wait-for-install")
    segments.size.should eq(1)
    segments[0].tasks.should eq(["cnf_install"])
    segments[0].args.named["cnf-config"].should eq("x.yml")
    segments[0].args.named["timeout"].should eq("30")
    # Flags keep the word tasks already read.
    segments[0].args.raw.should contain("skip_wait_for_install")
  end

  it "accepts options anywhere on the line and runs several tasks in order", tags: ["points"] do
    segments = parse("--strict", "liveness", "readiness", "--results-dir", "out")
    segments.size.should eq(1)
    segments[0].tasks.should eq(["liveness", "readiness"])
    segments[0].args.raw.should eq(["strict"])
    CLIInvocation.tasks.should eq(["liveness", "readiness"])
    CLIInvocation.option("results-dir").should eq("out")
    invoked_task?("readiness").should be_true
    invoked_task?("strict").should be_false
  end

  it "turns --skip into the exclusion SAM honors, resolving aliases", tags: ["points"] do
    segments = parse("all", "--skip", "resilience", "--skip=liveness")
    segments[0].args.raw.should eq(["~resilience", "~liveness"])
    # A top-level alias names the task it points at.
    segments = parse("platform", "--skip", "k8s_conformance")
    segments[0].args.raw.first.to_s.should start_with("~")
    segments[0].args.raw.first.to_s.should_not eq("~k8s_conformance") if TaskAliases["k8s_conformance"]?
  end

  it "keeps the legacy spellings working until they are removed", tags: ["points"] do
    segments = parse("cnf_install", "cnf-config=x.yml", "timeout=30", "skip_wait_for_install", "~liveness", "@", "cert", "exclude=liveness readiness")
    segments.size.should eq(2)
    segments[0].tasks.should eq(["cnf_install"])
    segments[0].args.named["cnf-config"].should eq("x.yml")
    segments[0].args.raw.should eq(["skip_wait_for_install", "~liveness"])
    segments[1].tasks.should eq(["cert"])
    segments[1].args.named["exclude"].should eq("liveness readiness")
    CLIInvocation.tasks.should eq(["cnf_install", "cert"])
  end

  it "preserves '=' inside values", tags: ["points"] do
    parse("cnf_install", "--cnf-config=a=b")[0].args.named["cnf-config"].should eq("a=b")
    parse("cnf_install", "cnf-config=a=b")[0].args.named["cnf-config"].should eq("a=b")
  end

  it "leaves help and completion topics alone", tags: ["points"] do
    parse("help", "tasks")[0].args.raw.should eq(["tasks"])
    parse("help", "liveness")[0].tasks.should eq(["help"])
    parse("completion", "zsh")[0].args.raw.should eq(["zsh"])
  end

  it "reports every usage error at once, with suggestions", tags: ["points"] do
    errors = usage_error("cnf_install", "--cnf-confg", "x", "--timeout", "abc", "--strict=yes", "--skip", "livenes", "bogus")
    errors.join("\n").should contain("Unknown option '--cnf-confg'. Did you mean '--cnf-config'?")
    errors.join("\n").should contain("'abc' is not a number")
    errors.join("\n").should contain("'--strict' takes no value")
    errors.join("\n").should contain("Unknown task 'livenes' given to '--skip'. Did you mean 'liveness'?")
    errors.join("\n").should contain("Unknown flag 'bogus'")
    errors.size.should eq(5)

    usage_error("cnf_install", "--cnf-config").join.should contain("requires a value")
    usage_error("cnf_install", "--kubeconfig", "/nonexistent").join.should contain("is not a file")
    usage_error("version", "cnf-path=x").join.should contain("Unknown argument 'cnf-path='")
    usage_error("version", "--exclude", "x").join.should contain("Unknown option '--exclude'")
    usage_error("version", "-x").join.should contain("Unknown option '-x'")
  end

  it "sets KUBECONFIG from --kubeconfig", tags: ["points"] do
    original = ENV["KUBECONFIG"]?
    file = File.tempname("kubeconfig")
    File.write(file, "")
    begin
      parse("version", "--kubeconfig", file)
      ENV["KUBECONFIG"].should eq(file)
    ensure
      File.delete?(file)
      original ? (ENV["KUBECONFIG"] = original) : ENV.delete("KUBECONFIG")
    end
  end
end
