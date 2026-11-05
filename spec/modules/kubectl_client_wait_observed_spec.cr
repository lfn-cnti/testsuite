require "../spec_helper.cr"

# A DaemonSet the API server has created but its controller has not seen yet
# carries a status of zeros, which read as 0 of 0 passed for ready and made
# the cluster-tools gate stop setup on a busy runner (free5gc/free5gc-helm#44).
# On a quiet cluster the controller is too fast to catch in that state, so
# these specs stop the controller manager on the kind control-plane node (by
# moving its static pod manifest away) for as long as they need, and always
# start it again. They run on their own tag, so their kind cluster is theirs,
# and only on kind (see control_plane_node).

CONTROLLER_MANIFEST        = "/etc/kubernetes/manifests/kube-controller-manager.yaml"
CONTROLLER_MANIFEST_PAUSED = "/etc/kubernetes/kube-controller-manager.yaml.paused"

# The control-plane node, which on kind is a Docker container these specs
# can reach. On any other cluster they cannot stop its controller manager:
# exclude them there with `crystal spec --tag '~controller_paused'`.
private def control_plane_node : String
  out = ShellCmd.run("kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}'")[:output].strip
  out.should_not be_empty
  unless ShellCmd.run("docker inspect -f '{{.State.Running}}' #{out}")[:output].strip == "true"
    fail "the controller_paused specs need a kind cluster: #{out} is not a running Docker container here; run `crystal spec --tag '~controller_paused'` on other clusters"
  end
  out
end

private def controller_manager_running?(node : String) : Bool
  !ShellCmd.run("docker exec #{node} crictl ps -q --name kube-controller-manager")[:output].strip.empty?
end

# Waits up to `seconds` for the controller manager to be running (or stopped).
private def wait_controller_manager(node : String, running : Bool, seconds : Int32)
  seconds.times do
    return if controller_manager_running?(node) == running
    sleep 1.seconds
  end
  fail "kube-controller-manager on #{node} is #{running ? "not running" : "still running"} after #{seconds}s"
end

private def pause_controller_manager(node : String)
  ShellCmd.run("docker exec #{node} mv #{CONTROLLER_MANIFEST} #{CONTROLLER_MANIFEST_PAUSED}")[:status].success?.should be_true
  wait_controller_manager(node, running: false, seconds: 90)
end

# Safe to call whether or not the controller manager is paused.
private def resume_controller_manager(node : String)
  ShellCmd.run("docker exec #{node} sh -c 'test -f #{CONTROLLER_MANIFEST_PAUSED} && mv #{CONTROLLER_MANIFEST_PAUSED} #{CONTROLLER_MANIFEST} || true'")
  wait_controller_manager(node, running: true, seconds: 180)
end

describe "KubectlClient::Wait on a DaemonSet its controller has not observed" do
  it "keeps waiting while the status is the API server's zeros, and is ready once the controller has observed it", tags: ["controller_paused"] do
    node = control_plane_node
    namespace = "cnti-observed-spec"
    manifest = File.tempname("observed-daemonset", ".yml")
    # The pause image is on every kind node already: nothing to pull. Its
    # pod meets the restricted Pod Security level, which the CI kind clusters
    # enforce cluster-wide.
    File.write(manifest, <<-YAML)
      apiVersion: apps/v1
      kind: DaemonSet
      metadata:
        name: observed-spec
      spec:
        selector:
          matchLabels:
            app: observed-spec
        template:
          metadata:
            labels:
              app: observed-spec
          spec:
            securityContext:
              runAsNonRoot: true
              runAsUser: 65535
              seccompProfile:
                type: RuntimeDefault
            containers:
              - name: pause
                image: registry.k8s.io/pause:3.10
                securityContext:
                  allowPrivilegeEscalation: false
                  capabilities:
                    drop: ["ALL"]
      YAML
    begin
      KubectlClient::Apply.namespace(namespace)
      begin
        pause_controller_manager(node)
        KubectlClient::Apply.file(manifest, namespace: namespace)
        live = KubectlClient::Get.resource("daemonset", "observed-spec", namespace)
        # The state free5GC's runner hit by timing: zeros, nothing observed.
        live.dig?("status", "desiredNumberScheduled").try(&.as_i).should eq(0)
        live.dig?("status", "observedGeneration").should be_nil
        KubectlClient::Get.replica_counts("DaemonSet", live).should eq({current: -1, desired: -1, unavailable: -1})
        KubectlClient::Wait.resource_wait_for_install("DaemonSet", "observed-spec", wait_count: 10, namespace: namespace).should be_false
      ensure
        resume_controller_manager(node)
      end
      KubectlClient::Wait.resource_wait_for_install("DaemonSet", "observed-spec", wait_count: 180, namespace: namespace).should be_true
      KubectlClient::Get.replica_count("DaemonSet", "observed-spec", namespace)[:desired].should be > 0
    ensure
      File.delete?(manifest)
      KubectlClient::Delete.resource("namespace", namespace) rescue nil
    end
  end

  it "lets setup install cluster-tools when its controller observes the DaemonSet late (free5gc/free5gc-helm#44)", tags: ["controller_paused"] do
    node = control_plane_node
    # As setup creates it: the helper's pods are privileged, which the
    # namespace's Pod Security level has to allow.
    SuiteNamespaces.ensure_exists(ClusterTools.namespace)
    ClusterTools.uninstall rescue nil
    done = Channel(Bool | Exception).new(1)
    begin
      pause_controller_manager(node)
      spawn do
        done.send(ClusterTools.install)
      rescue ex
        done.send(ex)
      end
      # Wait until the install has applied the DaemonSet and it sits in the
      # state free5GC's runner hit: the API server's zeros, not observed.
      unobserved = false
      90.times do
        live = KubectlClient::Get.resource("daemonset", "cluster-tools", ClusterTools.namespace) rescue nil
        if live && live.dig?("status", "observedGeneration").nil? &&
           KubectlClient::Get.replica_counts("DaemonSet", live)[:desired] == -1
          unobserved = true
          break
        end
        sleep 1.seconds
      end
      unobserved.should be_true
      # While the controller stays away, the install must keep waiting.
      # Before the fix the gate raised at once: "no node of the cluster
      # schedules the DaemonSet".
      select
      when early = done.receive
        fail "ClusterTools.install ended while the DaemonSet was unobserved: #{early.is_a?(Exception) ? early.message : early}"
      when timeout(10.seconds)
      end
      # The controller comes back late, as it does on a busy runner.
      resume_controller_manager(node)
      select
      when outcome = done.receive
        raise outcome if outcome.is_a?(Exception)
        outcome.should be_true
      when timeout((ClusterTools.ready_timeout + 60).seconds)
        fail "ClusterTools.install did not end after the controller manager came back"
      end
    ensure
      resume_controller_manager(node)
    end
  end
end
