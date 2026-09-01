require "./utils/embedded_file_manager.cr"

ESSENTIAL_PASSED_THRESHOLD = 15
# The one directory the suite owns in the user's working directory. Everything
# a run writes into the CWD lives under it: the installed CNF's files and the
# results (unless results-dir/CNF_TESTSUITE_RESULTS_DIR redirect those).
CNTI_DIR = "cnti"

CNF_DIR = File.join(CNTI_DIR, "installed-cnf")
DEPLOYMENTS_DIR = File.join(CNF_DIR, "deployments")
CNF_TEMP_FILES_DIR = File.join(CNF_DIR, "temp_files")
CNF_INSTALL_LOG_FILE = File.join(CNF_TEMP_FILES_DIR, "installation.log")
CONFIG_FILE = "cnf-testsuite.yml"
COMMON_MANIFEST_FILE_PATH = "#{CNF_DIR}/common_manifest.yml"
DEPLOYMENT_MANIFEST_FILE_NAME = "deployment_manifest.yml"
# todo move to helm module
# CHART_YAML = "Chart.yaml"
DEFAULT_POINTSFILENAME = "points_v1.yml"
IGNORED_SECRET_TYPES = ["kubernetes.io/service-account-token", "kubernetes.io/dockercfg", "kubernetes.io/dockerconfigjson", "helm.sh/release.v1"]
EMPTY_JSON = JSON.parse(%({}))
EMPTY_JSON_ARRAY = JSON.parse(%([]))
# Matched against the basename of a container's PID 1 executable: tini (also
# as tini-static, and as docker-init, the copy Docker ships), dumb-init, and
# s6-svscan (PID 1 once s6-overlay's /init has handed over).
SPECIALIZED_INIT_SYSTEMS = ["tini", "tini-static", "docker-init", "dumb-init", "s6-svscan"]
ROLLING_VERSION_CHANGE_TEST_NAMES = ["rolling_update", "rolling_downgrade", "rolling_version_change"]
WORKLOAD_RESOURCE_KIND_NAMES = ["replicaset", "deployment", "statefulset", "pod", "daemonset"]

TESTSUITE_NAMESPACE = "cnf-testsuite"
DEFAULT_CNF_NAMESPACE = "cnf-default"
# (kosstennbl) Needed only for manifest deployments, where we don't have control over installation namespace
CLUSTER_DEFAULT_NAMESPACE = "default"

#Embedded global text variables
EmbeddedFileManager.node_failure_values
EmbeddedFileManager.chaos_network_loss
EmbeddedFileManager.chaos_cpu_hog
EmbeddedFileManager.chaos_container_kill
EmbeddedFileManager.litmus_rbac
EmbeddedFileManager.enforce_image_tag
EmbeddedFileManager.constraint_template
EmbeddedFileManager.fluentd_values
EmbeddedFileManager.fluentbit_values
EmbeddedFileManager.ueransim_helmconfig

EXCLUDE_NAMESPACES = [
  "kube-system",
  "kube-public",
  "kube-node-lease",
  "local-path-storage",
  "litmus",
  TESTSUITE_NAMESPACE
]
