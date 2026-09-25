require "../spec_helper"

describe "CNFInstall.resolve_helm_values" do
  it "resolves values files next to the config, and leaves the rest as written", tags: ["points"] do
    dir = File.tempname("helm-values")
    FileUtils.mkdir_p(File.join(dir, "ci"))
    File.write(File.join(dir, "ci", "values.yaml"), "a: 1\n")
    File.write(File.join(dir, "ci", "ca.crt"), "x\n")
    abs = File.expand_path(File.join(dir, "ci", "values.yaml"))
    ca = File.expand_path(File.join(dir, "ci", "ca.crt"))

    CNFInstall.resolve_helm_values("--values ci/values.yaml", dir).should eq("--values #{abs}")
    CNFInstall.resolve_helm_values("-f ci/values.yaml --set image.tag=v1", dir).should eq("-f #{abs} --set image.tag=v1")
    CNFInstall.resolve_helm_values("--values=ci/values.yaml", dir).should eq("--values=#{abs}")
    # A file that is not next to the config stays relative to the working directory.
    CNFInstall.resolve_helm_values("-f ci/values.yaml,ci/other.yaml", dir).should eq("-f #{abs},ci/other.yaml")
    CNFInstall.resolve_helm_values("-f ./example-cnfs/ocudu/gnb-values.yaml", dir).should eq("-f ./example-cnfs/ocudu/gnb-values.yaml")
    CNFInstall.resolve_helm_values("--set-file tls.crt=ci/ca.crt,tls.key=missing.key", dir).should eq("--set-file tls.crt=#{ca},tls.key=missing.key")
    CNFInstall.resolve_helm_values("-f /etc/values.yaml -f https://example.com/v.yaml --set x=ci/values.yaml", dir).should eq("-f /etc/values.yaml -f https://example.com/v.yaml --set x=ci/values.yaml")
  ensure
    FileUtils.rm_rf(dir.not_nil!)
  end
end
