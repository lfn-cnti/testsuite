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

describe "Helm.redact_for_log" do
  it "masks the values of --set flags in a logged command, and keeps the keys and --set-file", tags: ["points"] do
    command = %(helm install db chart --set auth.password=s3cret,auth.user=app --set-string 'token=a b' --set-string auth.key="first second" --set-json=cfg={"k":"v"} --set-file ca=certs/ca.pem -f values.yaml)
    masked = Helm.redact_for_log(command)
    masked.should eq(%(helm install db chart --set auth.password=***,auth.user=*** --set-string token=*** --set-string auth.key=*** --set-json=cfg=*** --set-file ca=certs/ca.pem -f values.yaml))
    ["s3cret", "first", "second"].each { |secret| masked.should_not contain(secret) }
  end

  it "removes the credentials from the URLs of a chart or a values file", tags: ["points"] do
    command = %(helm install db oci://robot:t0ken@registry.example/charts/db -f https://user:pa55@example.com/values.yaml?sig=abc&exp=1 -f values.yaml)
    masked = Helm.redact_for_log(command)
    masked.should eq(%(helm install db oci://***@registry.example/charts/db -f https://***@example.com/values.yaml?sig=***&exp=*** -f values.yaml))
    ["t0ken", "pa55", "abc"].each { |secret| masked.should_not contain(secret) }
  end

  it "takes the userinfo from the authority only, up to its last @", tags: ["points"] do
    Helm.redact_for_log("helm install db -f https://user:p@ss@host.example/v.yaml").should eq("helm install db -f https://***@host.example/v.yaml")
    Helm.redact_for_log("helm install db -f https://example.com/v.yaml?email=a@b.com").should eq("helm install db -f https://example.com/v.yaml?email=***")
  end

  it "masks what shell escapes, quoted query values and JSON values would carry past a pattern", tags: ["points"] do
    command = %q(helm install db chart --set password=first\ second -f https://example.com/values.yaml?token='secret' --set-json 'cfg={"password":"prefix,SECRET=suffix"}')
    masked = Helm.redact_for_log(command)
    masked.should eq(%(helm install db chart --set password=*** -f https://example.com/values.yaml?token=*** --set-json cfg=***))
    ["second", "secret", "SECRET", "suffix"].each { |secret| masked.should_not contain(secret) }
  end

  it "logs nothing from the first --set on when a quote is not closed", tags: ["points"] do
    Helm.redact_for_log(%(helm install db chart --set password="oops -f values.yaml)).should eq("helm install db chart --set ... (rest not logged: unbalanced quotes)")
  end
end
