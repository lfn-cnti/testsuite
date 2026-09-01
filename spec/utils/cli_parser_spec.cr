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
    invocation = parse("cnf_install", "--cnf-config", "x.yml", "--timeout=30", "--skip-wait-for-install")
    invocation.tasks.should eq(["cnf_install"])
    invocation.args.named["cnf-config"].should eq("x.yml")
    invocation.args.named["timeout"].should eq("30")
    # Flags keep the word tasks already read.
    invocation.args.raw.should contain("skip_wait_for_install")
  end

  it "accepts options anywhere on the line and runs several tasks in order", tags: ["points"] do
    invocation = parse("--strict", "liveness", "readiness", "--results-dir", "out")
    invocation.tasks.should eq(["liveness", "readiness"])
    invocation.args.raw.should eq(["strict"])
    CLIInvocation.tasks.should eq(["liveness", "readiness"])
    CLIInvocation.option("results-dir").should eq("out")
    invoked_task?("readiness").should be_true
    invoked_task?("strict").should be_false
  end

  it "turns --skip into the exclusion SAM honors, resolving aliases", tags: ["points"] do
    parse("all", "--skip", "resilience", "--skip=liveness").args.raw.should eq(["~resilience", "~liveness"])
  end

  it "names the replacement for every retired spelling", tags: ["points"] do
    errors = usage_error("cnf_install", "cnf-config=x.yml", "timeout=30", "skip_wait_for_install", "~liveness", "@", "cert", "exclude=liveness readiness")
    errors.should eq([
      "'cnf-config=' is no longer accepted: use `--cnf-config PATH`.",
      "'timeout=' is no longer accepted: use `--timeout SECONDS`.",
      "'skip_wait_for_install' is no longer accepted: use `--skip-wait-for-install`.",
      "'~liveness' is no longer accepted: use `--skip liveness`.",
      "'@' is no longer needed: list the tasks to run, e.g. `cnti-testsuite liveness readiness`.",
      "'exclude=' is no longer accepted: use `--skip TASK`, once per task.",
    ])
  end

  it "preserves '=' inside values", tags: ["points"] do
    parse("cnf_install", "--cnf-config=a=b").args.named["cnf-config"].should eq("a=b")
    parse("cnf_install", "--cnf-config", "a=b").args.named["cnf-config"].should eq("a=b")
  end

  it "leaves help and completion topics alone", tags: ["points"] do
    parse("help", "tasks").args.raw.should eq(["tasks"])
    parse("help", "liveness").tasks.should eq(["help"])
    parse("completion", "zsh").args.raw.should eq(["zsh"])
  end

  it "reports every usage error at once, with suggestions", tags: ["points"] do
    errors = usage_error("cnf_install", "--cnf-confg", "x", "--timeout", "abc", "--strict=yes", "--skip", "livenes", "bogus")
    errors.join("\n").should contain("Unknown option '--cnf-confg'. Did you mean '--cnf-config'?")
    errors.join("\n").should contain("'abc' is not a number")
    errors.join("\n").should contain("'--strict' takes no value")
    errors.join("\n").should contain("Unknown task 'livenes' given to '--skip'. Did you mean 'liveness'?")
    errors.join("\n").should contain("Unknown argument 'bogus'")
    errors.size.should eq(5)

    usage_error("cnf_install", "--cnf-config").join.should contain("requires a value")
    usage_error("cnf_install", "--kubeconfig", "/nonexistent").join.should contain("is not a file")
    usage_error("version", "cnf-path=x").join.should contain("Unknown argument 'cnf-path='. Options are written --name VALUE.")
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
