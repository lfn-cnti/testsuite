require "../spec_helper"
require "../../src/tasks/utils/hugepages_lint"

# Pure unit specs for the hugepages static lint. A malformed hugepages manifest
# is rejected by the Kubernetes API server at apply time, so it cannot be
# installed to a live cluster; the lint is therefore exercised directly against
# rendered manifest YAML here, which also makes every disposition reachable.
private def ymls(manifest : String) : Array(YAML::Any)
  YAML.parse_all(manifest).reject { |x| x.raw.nil? }
end

describe "HugepagesLint" do
  it "reports no violations for a well-formed hugepages consumer", tags: ["points"] do
    result = HugepagesLint.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: good
        namespace: cnti
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
              resources:
                requests:
                  memory: 128Mi
                  hugepages-2Mi: 256Mi
                limits:
                  hugepages-2Mi: 256Mi
            volumes:
            - name: hp
              emptyDir:
                medium: HugePages-2Mi
      YAML
    result[:hugepage_containers].should eq(1)
    result[:violations].should be_empty
  end

  it "compares hugepages request and limit by canonical value, not string", tags: ["points"] do
    # 1Gi == 1024Mi: equal amounts written differently must not be a violation.
    result = HugepagesLint.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: canonical
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
              resources:
                requests:
                  cpu: "1"
                  hugepages-1Gi: 1Gi
                limits:
                  hugepages-1Gi: 1024Mi
      YAML
    result[:hugepage_containers].should eq(1)
    result[:violations].should be_empty
  end

  it "flags request != limit, a missing cpu/memory request, and a mismatched emptyDir medium", tags: ["points"] do
    result = HugepagesLint.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: bad
        namespace: cnti
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
              resources:
                requests:
                  hugepages-2Mi: 100Mi
                limits:
                  hugepages-2Mi: 200Mi
            volumes:
            - name: hp
              emptyDir:
                medium: HugePages-1Gi
      YAML
    result[:hugepage_containers].should eq(1)
    reasons = result[:violations].map(&.reason)
    reasons.any?(&.includes?("request")).should be_true          # (a) request != limit
    reasons.any?(&.includes?("cpu or memory")).should be_true    # (b) no cpu/memory request
    reasons.any?(&.includes?("does not match")).should be_true   # (c) emptyDir medium mismatch
    result[:violations].first.kind.should eq("Deployment")
    result[:violations].first.name.should eq("bad")
    result[:violations].first.container.should eq("app")
  end

  it "allows a generic HugePages emptyDir medium (no size named)", tags: ["points"] do
    result = HugepagesLint.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: generic-medium
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
              resources:
                requests:
                  memory: 64Mi
                  hugepages-2Mi: 64Mi
                limits:
                  hugepages-2Mi: 64Mi
            volumes:
            - name: hp
              emptyDir:
                medium: HugePages
      YAML
    result[:violations].should be_empty
  end

  it "inspects a bare Pod's containers too", tags: ["points"] do
    result = HugepagesLint.check(ymls(<<-YAML))
      apiVersion: v1
      kind: Pod
      metadata:
        name: bare
      spec:
        containers:
        - name: app
          image: nginx
          resources:
            requests:
              hugepages-2Mi: 100Mi
            limits:
              hugepages-2Mi: 200Mi
      YAML
    result[:hugepage_containers].should eq(1)
    result[:violations].map(&.reason).any?(&.includes?("request")).should be_true
  end

  it "is not applicable when no container requests hugepages", tags: ["points"] do
    result = HugepagesLint.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: no-hugepages
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
              resources:
                requests:
                  cpu: 100m
                  memory: 64Mi
      YAML
    result[:hugepage_containers].should eq(0)
    result[:violations].should be_empty
  end
end
