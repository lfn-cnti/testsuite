module Helm
  DEFAULT_ARCH              = "linux-amd64"
  DEFAULT_LOCAL_BINARY_PATH = "tools/helm"
  BASE_CONFIG               = "./config.yml"

  # helm CMD errors
  RELEASE_NOT_FOUND = "Release not loaded:"
  REPO_NOT_FOUND = "not found"
end
