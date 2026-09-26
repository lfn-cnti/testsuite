require "../spec_helper"

describe "Helm chart dependencies" do
  it "finds the dependencies a chart declares and which of them charts/ lacks", tags: ["points"] do
    dir = File.tempname("chart-deps")
    FileUtils.mkdir_p(File.join(dir, "charts"))
    File.write(File.join(dir, "Chart.yaml"), <<-YAML
      apiVersion: v2
      name: app
      version: 0.1.0
      dependencies:
        - name: foo
          version: 1.2.0
          repository: https://charts.example.com
        - name: foo-bar
          version: 0.3.0
          repository: file://../foo-bar
        - name: etcd
          version: 12.0.18
          repository: oci://registry.example.com/charts
        - name: mongodb
          condition: deployMongoDb
      YAML
    )
    File.write(File.join(dir, "charts", "foo-bar-0.3.0.tgz"), "")
    Dir.mkdir(File.join(dir, "charts", "etcd"))
    # A vendored subchart with the version in its directory name and no version
    # constraint in Chart.yaml, the way free5gc ships MongoDB.
    Dir.mkdir(File.join(dir, "charts", "mongodb-15.6.0"))

    Helm.chart_dependencies(dir).map(&.[:name]).should eq(["foo", "foo-bar", "etcd", "mongodb"])
    # foo-bar-0.3.0.tgz is foo-bar's package, not foo's; mongodb-15.6.0/ is mongodb.
    Helm.missing_dependencies(dir).map(&.[:name]).should eq(["foo"])
  ensure
    FileUtils.rm_rf(dir.not_nil!)
  end

  it "makes a copied chart's file:// dependencies absolute, relative to where it came from", tags: ["points"] do
    copy = File.tempname("chart-copy")
    FileUtils.mkdir_p(copy)
    File.write(File.join(copy, "Chart.yaml"), "dependencies:\n  - name: settings\n    repository: file://../settings\n  - name: abs\n    repository: file:///opt/abs\n")
    CNFInstall.absolutize_local_dependencies(copy, "/src/charts/umbrella")
    text = File.read(File.join(copy, "Chart.yaml"))
    text.should contain("repository: file:///src/charts/settings")
    text.should contain("repository: file:///opt/abs")
  ensure
    FileUtils.rm_rf(copy.not_nil!)
  end
end
