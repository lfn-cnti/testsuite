require "../spec_helper"
require "../../src/tasks/utils/cli_args_validation"

# Runs the generated bash completion function the way readline would: with the
# command line up to the cursor in COMP_LINE/COMP_POINT and bash's default word
# breaks, returning what would be offered.
private def bash_completions(line : String) : Array(String)
  script = File.tempname("cnf-completion", ".bash")
  probe = File.tempname("cnf-completion-probe", ".bash")
  File.write(script, ShellCmd.run_testsuite("completion bash")[:output])
  # Written to a file rather than passed inline: the probe needs bash's own
  # quoting ($'...') which does not survive being quoted for sh a second time.
  File.write(probe, <<-BASH)
    source #{script}
    COMP_WORDBREAKS=$' \\t\\n"\\'><=;|&(:'
    COMP_LINE=#{Process.quote(line)}
    COMP_POINT=${#COMP_LINE}
    _cnf_testsuite_completions
    printf '%s\\n' "${COMPREPLY[@]}"
    BASH
  begin
    result = ShellCmd.run("bash #{probe}", log_prefix: "bash_completions")
    result[:output].split("\n").reject(&.empty?)
  ensure
    File.delete?(script)
    File.delete?(probe)
  end
end

describe "Shell completion" do
  it "registers the function for the invoked binary and offers no internal task", tags: ["points"] do
    result = ShellCmd.run_testsuite("completion")
    result[:status].exit_code.should eq(0)
    result[:output].should contain("complete -F _cnf_testsuite_completions cnf-testsuite")
    result[:output].should contain("setup:install_kubescape")
    result[:output].should_not contain("_divide_by_zero")
    result[:output].should_not contain("generate:")

    ShellCmd.run_testsuite("completion zsh")[:output].should contain("bashcompinit")
    ShellCmd.run_testsuite("completion fish")[:status].exit_code.should eq(USAGE_EXIT_CODE)
  end

  it "completes namespaced task paths, and only the part after the colon bash splits on", tags: ["points"] do
    bash_completions("cnf-testsuite setup:install_kubes").should eq(["install_kubescape"])
    first = bash_completions("cnf-testsuite ")
    first.should contain("setup:install_kubescape")
    first.should contain("liveness")
    first.should_not contain("_divide_by_zero")
    first.size.should eq(first.uniq.size)
  end

  it "completes flags, key= arguments, exclusions and tasks after the separator", tags: ["points"] do
    after_task = bash_completions("cnf-testsuite all ")
    after_task.should contain("strict")
    after_task.should contain("cnf-config=")
    after_task.should contain("@")
    after_task.should_not contain("liveness")

    bash_completions("cnf-testsuite all ~readi").should eq(["~readiness"])
    bash_completions("cnf-testsuite liveness @ readi").should eq(["readiness"])
    bash_completions("cnf-testsuite -l deb").should eq(["debug"])
    bash_completions("cnf-testsuite -l debug live").should eq(["liveness"])
    bash_completions("cnf-testsuite help tas").should eq(["tasks"])
    bash_completions("cnf-testsuite completion ").should eq(["bash", "zsh"])
  end

  it "completes file names after path-valued arguments", tags: ["points"] do
    bash_completions("cnf-testsuite cnf_install cnf-config=spec/fixtu").should eq(["spec/fixtures/"])
    bash_completions("cnf-testsuite cnf_install timeout=").should be_empty
  end
end
