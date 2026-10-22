# coding: utf-8
require "../spec_helper"

describe "CNFInstall::Manifest" do
  describe ".split_by_source" do
    it "keeps the shipped documents apart from the ones read back from the cluster", tags: ["manifest"] do
      manifest = <<-YAML
        ---
        # Source: helm_chart:coredns (Deployment/coredns)
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: coredns
        ---
        # Source: owned_by MongoDBCommunity/mongodb (StatefulSet/mongodb)
        apiVersion: apps/v1
        kind: StatefulSet
        metadata:
          name: mongodb
          uid: 1234
        ---
        # Source: crd_group_filter (mongodbcommunity.mongodb.com) (CustomResourceDefinition/mongodbcommunity.mongodbcommunity.mongodb.com)
        apiVersion: apiextensions.k8s.io/v1
        kind: CustomResourceDefinition
        metadata:
          name: mongodbcommunity.mongodbcommunity.mongodb.com
        ---
        # Source: manifest:replica-set (MongoDBCommunity/mongodb)
        apiVersion: mongodbcommunity.mongodb.com/v1
        kind: MongoDBCommunity
        metadata:
          name: mongodb
        ---
        # Source: label_filter (app=x) (ConfigMap/labelled)
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: labelled
        YAML
      parts = CNFInstall::Manifest.split_by_source(manifest)
      shipped = CNFInstall::Manifest.manifest_string_to_ymls(parts[:shipped]).map { |y| y["kind"].as_s }
      read_back = CNFInstall::Manifest.manifest_string_to_ymls(parts[:read_back]).map { |y| y["kind"].as_s }
      shipped.should eq(["Deployment", "MongoDBCommunity"])
      read_back.should eq(["StatefulSet", "CustomResourceDefinition", "ConfigMap"])
    end
  end

  describe ".strip_live_fields" do
    it "removes what the server assigned and keeps the rest", tags: ["manifest"] do
      ymls = CNFInstall::Manifest.manifest_string_to_ymls(<<-YAML)
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: labelled
          namespace: x
          uid: 1234
          resourceVersion: "5"
          creationTimestamp: "2026-10-22T00:00:00Z"
          managedFields: []
          annotations:
            kubernetes.io/ingress.class: nginx
        data:
          k: v
        status:
          phase: Active
        YAML
      cleaned = CNFInstall::Manifest.strip_live_fields(ymls).first
      cleaned.dig?("metadata", "uid").should be_nil
      cleaned.dig?("metadata", "resourceVersion").should be_nil
      cleaned.dig?("metadata", "creationTimestamp").should be_nil
      cleaned.dig?("metadata", "managedFields").should be_nil
      cleaned["status"]?.should be_nil
      cleaned.dig("metadata", "annotations", "kubernetes.io/ingress.class").as_s.should eq("nginx")
      cleaned.dig("data", "k").as_s.should eq("v")
    end
  end

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

    it "returns an empty array and does not raise when given invalid YAML", tags: ["manifest"] do
      result = CNFInstall::Manifest.manifest_string_to_ymls("{ invalid: yaml: :")
      result.size.should eq(0)
    end
  end
end
