require "totem"
require "colorize"
require "log"
require "halite"

module EmbeddedFileManager
  macro node_failure_values
    NODE_FAILED_VALUES = Base64.decode_string("{{ `cat ./embedded_files/node_failure_values.yml  | base64`}}")
  end
  macro reboot_daemon
    REBOOT_DAEMON = Base64.decode_string("{{ `cat ./tools/reboot_daemon/manifest.yml | base64` }}")
  end
  macro chaos_network_loss
    CHAOS_NETWORK_LOSS = Base64.decode_string("{{ `cat ./embedded_files/chaos_network_loss.yml  | base64`}}")
  end
  macro chaos_cpu_hog
    CHAOS_CPU_HOG = Base64.decode_string("{{ `cat ./embedded_files/chaos_cpu_hog.yml  | base64`}}")
  end
  macro chaos_container_kill
    CHAOS_CONTAINER_KILL = Base64.decode_string("{{ `cat ./embedded_files/chaos_container_kill.yml  | base64`}}")
  end
  macro enforce_image_tag
    ENFORCE_IMAGE_TAG = Base64.decode_string("{{ `cat ./embedded_files/enforce-image-tag.yml  | base64`}}")
  end
  macro constraint_template
    CONSTRAINT_TEMPLATE = Base64.decode_string("{{ `cat ./embedded_files/constraint_template.yml  | base64`}}")
  end
  macro disable_cni
    DISABLE_CNI = Base64.decode_string("{{ `cat ./embedded_files/kind-disable-cni.yaml  | base64`}}")
  end
  macro fluentd_values
    FLUENTD_VALUES = Base64.decode_string("{{ `cat ./embedded_files/fluentd-values.yml  | base64`}}")
  end
  macro fluentbit_values
    FLUENTBIT_VALUES = Base64.decode_string("{{ `cat ./embedded_files/fluentbit-values.yml | base64`}}")
  end
  macro fluentd_bitnami_values
    FLUENTD_BITNAMI_VALUES = Base64.decode_string("{{ `cat ./embedded_files/fluentd-bitnami-values.yml | base64`}}")
  end
  macro ueransim_helmconfig
    UERANSIM_HELMCONFIG = Base64.decode_string("{{ `cat ./embedded_files/ue.yaml | base64`}}")
  end
  # Minimal per-fault RBAC for the LitmusChaos faults the suite runs, as
  # published in the Litmus docs (chaos-charts stopped shipping rbac.yaml in 3.x).
  # Each manifest targets the "default" namespace; LitmusManager.install_fault
  # rewrites that to the CNF's namespace before applying.
  macro litmus_rbac
    LITMUS_RBAC = {
      "pod-network-latency" => Base64.decode_string("{{ `cat ./embedded_files/litmus_rbac/pod-network-latency.yaml | base64` }}"),
      "pod-network-corruption" => Base64.decode_string("{{ `cat ./embedded_files/litmus_rbac/pod-network-corruption.yaml | base64` }}"),
      "pod-network-duplication" => Base64.decode_string("{{ `cat ./embedded_files/litmus_rbac/pod-network-duplication.yaml | base64` }}"),
      "disk-fill" => Base64.decode_string("{{ `cat ./embedded_files/litmus_rbac/disk-fill.yaml | base64` }}"),
      "pod-delete" => Base64.decode_string("{{ `cat ./embedded_files/litmus_rbac/pod-delete.yaml | base64` }}"),
      "pod-memory-hog" => Base64.decode_string("{{ `cat ./embedded_files/litmus_rbac/pod-memory-hog.yaml | base64` }}"),
      "pod-io-stress" => Base64.decode_string("{{ `cat ./embedded_files/litmus_rbac/pod-io-stress.yaml | base64` }}"),
      "pod-dns-error" => Base64.decode_string("{{ `cat ./embedded_files/litmus_rbac/pod-dns-error.yaml | base64` }}"),
      "node-drain" => Base64.decode_string("{{ `cat ./embedded_files/litmus_rbac/node-drain.yaml | base64` }}"),
    }
  end
end
