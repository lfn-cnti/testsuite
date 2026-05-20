# coding: utf-8
require "../spec_helper"

describe "CNFInstall::Manifest" do
  describe ".manifest_string_to_ymls" do
    it "parses a standard multi-document YAML string", tags: ["manifest"] do
      manifest = <<-YAML
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: my-config
        ---
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: my-deploy
        YAML

      result = CNFInstall::Manifest.manifest_string_to_ymls(manifest)
      result.size.should eq(2)
      result[0]["kind"].as_s.should eq("ConfigMap")
      result[1]["kind"].as_s.should eq("Deployment")
    end

    it "parses a ConfigMap whose data contains embedded '---' without false splits", tags: ["manifest"] do
      manifest = <<-YAML
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: config-with-separator
        data:
          config.yaml: |
            key: value
            ---
            other: val
        ---
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: my-deploy
        YAML

      result = CNFInstall::Manifest.manifest_string_to_ymls(manifest)
      result.size.should eq(2)
      result[0]["kind"].as_s.should eq("ConfigMap")
      result[1]["kind"].as_s.should eq("Deployment")
    end

    it "parses a single-document YAML string (no separator)", tags: ["manifest"] do
      manifest = <<-YAML
        apiVersion: v1
        kind: Service
        metadata:
          name: my-svc
        YAML

      result = CNFInstall::Manifest.manifest_string_to_ymls(manifest)
      result.size.should eq(1)
      result[0]["kind"].as_s.should eq("Service")
    end

    it "returns an empty array for a blank string", tags: ["manifest"] do
      result = CNFInstall::Manifest.manifest_string_to_ymls("")
      result.size.should eq(0)
    end
  end
end
