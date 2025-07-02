module Helm
  # helm CMD errors
  RELEASE_NOT_FOUND         = "Release not loaded:|release: not found"
  REPO_NOT_FOUND            = "repo .* not found|is not a valid chart"
  CANNOT_REUSE_RELEASE_NAME = "cannot re-use a name that is still in use"
end
