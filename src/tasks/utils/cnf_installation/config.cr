require "yaml"
require "../utils.cr"
require "./config_versions/config_versions.cr"
require "./config_updater/config_updater.cr"

module CNFInstall
  module Config
    class Config < ConfigV2::Config
    end

    def self.parse_cnf_config_from_file(path_to_config)
      if !File.exists?(path_to_config)
        stdout_failure "No config found at #{path_to_config}."
        exit 1
      end
      yaml_content = File.read(path_to_config)
      begin
        parse_cnf_config_from_yaml(yaml_content)
      rescue exception
        stdout_failure "Error during parsing CNF config on #{path_to_config}"
        stdout_failure exception.message
        stdout_failure "Please check your config according to the config template."
        exit 1
      end
    end

    def self.parse_cnf_config_from_yaml(yaml_content)
      if !config_version_is_latest?(yaml_content)
        stdout_warning "CNF config version is not latest. Consider updating the CNF config with 'update_config' task."
        updater = CNFInstall::Config::ConfigUpdater.new(yaml_content)
        updater.transform
        yaml_content = updater.serialize_to_string
      end
      config = Config.from_yaml(yaml_content)
    end

    # Detects the config version.
    def self.detect_version(tmp_content : String) : ConfigVersion
      yaml_content = YAML.parse(tmp_content).as_h
      version_value = yaml_content["config_version"]?.try(&.to_s)

      if version_value
        begin
          ConfigVersion.parse(version_value.upcase)
        rescue ex : ArgumentError
          raise UnsupportedConfigVersionError.new(version_value)
        end
      else
        # Default to V1 if no version is specified
        ConfigVersion::V1
      end
    end

    def self.config_version_is_latest?(tmp_content : String) : Bool
      detect_version(tmp_content) == ConfigVersion::Latest
    end
  end
end
