require "file_utils"
require "colorize"
require "totem"
require "./utils.cr"

# TODO (rafal-lal): move stdout_ from here to main cnti
def kubectl_installation(verbose = false, offline_mode = false)
  gmsg = "No Global kubectl version found"
  lmsg = "No Local kubectl version found"
  gkubectl = kubectl_global_response
  Log.for("verbose").info { gkubectl } if verbose

  global_kubectl_version = kubectl_version(gkubectl, "client", verbose)

  if !global_kubectl_version.empty?
    gmsg = "Global kubectl found. Version: #{global_kubectl_version}"
    stdout_success gmsg

    version_test = acceptable_kubectl_version?(gkubectl, verbose)
    if version_test == false
      stdout_warning "Global kubectl client is more than 1 minor version ahead/behind server version"
    elsif version_test.nil? && offline_mode == false
      stdout_warning "Global kubectl client version could not be checked for compatibility with server. (Server not configured?)"
    elsif version_test.nil? && offline_mode == true
      stdout_warning "Global kubectl client version could not be checked for compatibility with server. Running in offline mode"
    end
  else
    stdout_warning gmsg
  end

  lkubectl = kubectl_local_response
  Log.for("verbose").info { lkubectl } if verbose

  local_kubectl_version = kubectl_version(lkubectl, "client", verbose)

  if !local_kubectl_version.empty?
    lmsg = "Local kubectl found. Version: #{local_kubectl_version}"
    stdout_success lmsg

    version_test = acceptable_kubectl_version?(lkubectl, verbose)
    if version_test == false
      stdout_warning "Local kubectl client is more than 1 minor version ahead/behind server version"
    elsif version_test.nil? && offline_mode == false
      stdout_warning "Local kubectl client version could not be checked for compatibility with server. (Server not configured?)"
    elsif version_test.nil? && offline_mode == true
      stdout_warning "Local kubectl client version could not be checked for compatibility with server. Running in offline mode"
    end
  else
    stdout_warning lmsg
  end

  # uncomment to fail the installation check
  # global_kubectl_version = nil
  # local_kubectl_version = nil
  # gmsg = "No Global kubectl version found"
  # lmsg = "No Local kubectl version found"
  if global_kubectl_version.empty? && local_kubectl_version.empty?
    stdout_failure "Kubectl not found"
    stdout_failure %Q(
    Linux installation instructions for Kubectl can be found here: https://kubernetes.io/docs/tasks/tools/install-kubectl/

    Install kubectl binary with curl on Linux
    Download the latest release with the command:

    curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
    To download a specific version, replace the $(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt) portion of the command with the specific version.

      For example, to download version v1.18.0 on Linux, type:

      curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.18.0/bin/linux/amd64/kubectl
    Make the kubectl binary executable.

      chmod +x ./kubectl
    Move the binary in to your PATH.

      sudo mv ./kubectl /usr/local/bin/kubectl
    Test to ensure the version you installed is up-to-date:

      kubectl version --client
    )
  end
  "#{lmsg} #{gmsg}"
end

def kubectl_global_response(verbose = false)
  status = Process.run("kubectl version -o json", shell: true, output: kubectl_response = IO::Memory.new, error: stderr = IO::Memory.new)
  Log.for("verbose").info { kubectl_response } if verbose
  kubectl_response.to_s
end

def kubectl_local_response(verbose = false)
  status = Process.run("#{local_kubectl_path} version -o json", shell: true, output: kubectl_response = IO::Memory.new, error: stderr = IO::Memory.new)
  Log.for("verbose").info { kubectl_response.to_s } if verbose
  kubectl_response.to_s
end

# Extracts Kubernetes client version or server version
#
# ```
# version = kubectl_version(kubectl_response, "client")
# version # => "1.12"
#
# version = kubectl_version(kubectl_response, "server")
# version # => "1.12"
# ```
#
# Returns the version as a string (Example: 1.12, 1.20, etc)
def kubectl_version(kubectl_response, version_for = "client", verbose = false)
  version_info_json = kubectl_response

  # The version skew or the server connection warnings are mutually exclusive.
  # Only one of them may be present in the output.

  # Strip the server connection warning if it exists in the output.
  # Server connection warning looks like below:
  # The connection to the server localhost:8080 was refused - did you specify the right host or port?
  if kubectl_response.includes?("The connection to the server")
    version_info_lines = version_info_json.split("\n")
    version_info_json = version_info_lines[0, version_info_lines.size - 1].join("\n")
  end

  # Strip the version skew warning if it exists in the output.
  # Version skew warning looks like below:
  # WARNING: version difference between client (1.28) and server (1.25) exceeds the supported minor version skew of +/-1
  if kubectl_response.includes?("WARNING: version difference between client")
    version_info_lines = version_info_json.split("\n")
    version_info_json = version_info_lines[0, version_info_lines.size - 1].join("\n")
  end

  # Look for the appropriate key depending on client or server version lookup
  version_key = "clientVersion"
  if version_for == "server"
    version_key = "serverVersion"
  end

  # Attempt to parse version output
  # Or return blank string if json parse exception
  begin
    version_data = JSON.parse(version_info_json)
  rescue ex : JSON::ParseException
    return ""
  end

  # If the specific server/client version info does not exist,
  # then return blank string
  if version_data.as_h.has_key?(version_key)
    version_info = version_data[version_key]
  else
    return ""
  end

  # If major and minor keys do not exist, then return blank string
  if version_info.as_h.has_key?("major") && version_info.as_h.has_key?("minor")
    major_version = version_info["major"].as_s
    minor_version = version_info["minor"].as_s
  else
    return ""
  end

  "#{major_version}.#{minor_version}"
end

# Check if client version is not too many versions behind server version
def acceptable_kubectl_version?(kubectl_response, verbose = false)
  client_version = kubectl_version(kubectl_response, "client", verbose).gsub("+", "").split(".")
  server_version = kubectl_version(kubectl_response, "server", verbose).gsub("+", "")

  # Return nil to indicate comparison was not possible due to missing server version.
  if server_version == ""
    return nil
  end

  server_version = server_version.split(".")

  # This check ensures major versions are same
  return false if server_version[0].to_i != client_version[0].to_i

  # This checks for minor versions
  server_minor_version = server_version[1].to_i
  client_minor_version = client_version[1].to_i

  # https://kubernetes.io/releases/version-skew-policy/
  # kubectl cannot be more than +/- 1 minor version away from the server
  return false if client_minor_version < (server_minor_version - 1) || client_minor_version > (server_minor_version + 1)
  return true
end
