require "../spec_helper"
require "../../src/tasks/utils/hugepages_volumes"

# Pure unit specs for the hugepages-volume backing lint. The failing manifests
# are accepted by the API server and fail only on the node, so they are exercised
# directly against rendered YAML here, which makes every outcome reachable.
private def ymls(manifest : String) : Array(YAML::Any)
  YAML.parse_all(manifest).reject { |x| x.raw.nil? }
end

describe "HugepagesVolumes" do
  it "passes when a HugePages-<size> volume is backed by a matching request", tags: ["points"] do
    result = HugepagesVolumes.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata: {name: good, namespace: cnti}
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
              resources:
                requests: {memory: 128Mi, hugepages-2Mi: 256Mi}
                limits: {hugepages-2Mi: 256Mi}
            volumes:
            - name: hp
              emptyDir: {medium: HugePages-2Mi}
      YAML
    result[:pods_with_hugepages_volume].should eq(1)
    result[:violations].should be_empty
  end

  it "accepts a hugepages backing given only as a limit", tags: ["points"] do
    # Kubernetes defaults the request from the limit, so a limit-only hugepages
    # resource is a valid backing.
    result = HugepagesVolumes.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata: {name: limit-only}
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
              resources:
                limits: {hugepages-2Mi: 256Mi}
            volumes:
            - name: hp
              emptyDir: {medium: HugePages-2Mi}
      YAML
    result[:violations].should be_empty
  end

  it "accepts a backing that comes from an init container", tags: ["points"] do
    result = HugepagesVolumes.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata: {name: init-backed}
      spec:
        template:
          spec:
            initContainers:
            - name: setup
              image: busybox
              resources:
                requests: {hugepages-2Mi: 128Mi}
            containers:
            - name: app
              image: nginx
            volumes:
            - name: hp
              emptyDir: {medium: HugePages-2Mi}
      YAML
    result[:violations].should be_empty
  end

  it "flags a HugePages-<size> volume that no container requests", tags: ["points"] do
    result = HugepagesVolumes.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata: {name: mismatch, namespace: cnti}
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
              resources:
                requests: {hugepages-2Mi: 128Mi}
            volumes:
            - name: hp
              emptyDir: {medium: HugePages-1Gi}
      YAML
    result[:pods_with_hugepages_volume].should eq(1)
    result[:violations].size.should eq(1)
    result[:violations].first.reason.should contain("hugepages-1Gi")
    result[:violations].first.volume.should eq("hp")
  end

  it "flags a hugepages volume with no hugepages request anywhere in the pod", tags: ["points"] do
    result = HugepagesVolumes.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata: {name: unbacked}
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
              resources:
                requests: {memory: 64Mi}
            volumes:
            - name: hp
              emptyDir: {medium: HugePages-2Mi}
      YAML
    result[:pods_with_hugepages_volume].should eq(1)
    result[:violations].size.should eq(1)
  end

  it "accepts a size-less HugePages medium backed by a single page size", tags: ["points"] do
    result = HugepagesVolumes.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata: {name: generic-ok}
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
              resources:
                requests: {hugepages-2Mi: 64Mi}
            volumes:
            - name: hp
              emptyDir: {medium: HugePages}
      YAML
    result[:violations].should be_empty
  end

  it "flags a size-less HugePages medium when the pod requests more than one page size", tags: ["points"] do
    result = HugepagesVolumes.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata: {name: generic-multi}
      spec:
        template:
          spec:
            containers:
            - name: a
              image: nginx
              resources:
                requests: {hugepages-2Mi: 64Mi}
            - name: b
              image: nginx
              resources:
                requests: {hugepages-1Gi: 1Gi}
            volumes:
            - name: hp
              emptyDir: {medium: HugePages}
      YAML
    result[:violations].size.should eq(1)
    result[:violations].first.reason.should contain("more than one page size")
  end

  it "flags a size-less HugePages medium with no hugepages request", tags: ["points"] do
    result = HugepagesVolumes.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata: {name: generic-none}
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
            volumes:
            - name: hp
              emptyDir: {medium: HugePages}
      YAML
    result[:violations].size.should eq(1)
  end

  it "is not applicable when no pod declares a hugepages volume", tags: ["points"] do
    # A container that asks for hugepages but mounts no HugePages emptyDir is
    # legitimate and leaves nothing to check.
    result = HugepagesVolumes.check(ymls(<<-YAML))
      apiVersion: apps/v1
      kind: Deployment
      metadata: {name: no-volume}
      spec:
        template:
          spec:
            containers:
            - name: app
              image: nginx
              resources:
                requests: {hugepages-2Mi: 128Mi}
      YAML
    result[:pods_with_hugepages_volume].should eq(0)
    result[:violations].should be_empty
  end

  it "inspects a bare Pod's volumes and containers too", tags: ["points"] do
    result = HugepagesVolumes.check(ymls(<<-YAML))
      apiVersion: v1
      kind: Pod
      metadata: {name: bare}
      spec:
        containers:
        - name: app
          image: nginx
          resources:
            requests: {hugepages-2Mi: 64Mi}
        volumes:
        - name: hp
          emptyDir: {medium: HugePages-1Gi}
      YAML
    result[:pods_with_hugepages_volume].should eq(1)
    result[:violations].size.should eq(1)
  end
end
