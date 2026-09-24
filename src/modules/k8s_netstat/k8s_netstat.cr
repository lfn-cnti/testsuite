require "../kubectl_client"
require "../cluster_tools"

# Observing TCP connections inside a container's network namespace, and
# recognising database containers; used by the shared_database test.
module Netstat
  alias Connection = NamedTuple(proto: String, recv: String, send: String,
    local_address: String, foreign_address: String, state: String)

  # kubectl exec cluster-tools-lhwkk -t -- nsenter -t 743858 -n netstat -n
  # Active Internet connections (w/o servers)
  # Proto Recv-Q Send-Q Local Address           Foreign Address         State
  # tcp        0      0 10.244.0.193:3306       10.244.0.194:36378      TIME_WAIT
  # Active UNIX domain sockets (w/o servers)
  # ...
  #
  # Only the TCP lines are kept; headers, footers and UNIX sockets are ignored.
  def self.parse(output : String) : Array(Connection)
    output.lines.compact_map do |line|
      m = line.match(/^(tcp6?)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)/)
      next nil unless m
      {proto: m[1], recv: m[2], send: m[3], local_address: m[4], foreign_address: m[5], state: m[6]}
    end
  end

  # "10.244.0.194:36378" -> "10.244.0.194"; "::ffff:10.244.0.194:36378" -> "10.244.0.194"
  def self.address_ip(address : String) : String
    ip = address.rpartition(":")[0]
    ip.lchop("::ffff:")
  end

  def self.address_port(address : String) : String
    address.rpartition(":")[2]
  end

  # Databases the shared_database test recognises, by the container image's
  # repository name (the last path segment, without tag or digest) and by
  # the port the database listens on.
  module Database
    alias Kind = NamedTuple(name: String, image: Regex, port: Int32)

    KNOWN = [
      {name: "MariaDB/MySQL", image: /^(mariadb|mysql|percona(-server)?)$/, port: 3306},
      {name: "PostgreSQL", image: /^postgres(ql)?$/, port: 5432},
      {name: "MongoDB", image: /^mongo(db)?$/, port: 27017},
      {name: "Redis", image: /^(redis|valkey)$/, port: 6379},
      {name: "Cassandra", image: /^cassandra$/, port: 9042},
      {name: "etcd", image: /^etcd$/, port: 2379},
    ] of Kind

    # "bitnamilegacy/mariadb:10.6" -> "mariadb"; "ghcr.io/x/postgresql@sha256:..." -> "postgresql"
    def self.repository_name(image : String) : String
      image.split("/").last.split("@").first.split(":").first.downcase
    end

    # The database a container runs, by image name first and by declared
    # port second; nil for anything else. Exporters, operators and proxies
    # carrying a database's name are not databases.
    def self.detect(container : JSON::Any) : NamedTuple(name: String, port: Int32)?
      image = container["image"]?.try(&.as_s?) || ""
      repo = repository_name(image)
      ports = (container["ports"]?.try(&.as_a?) || [] of JSON::Any).compact_map { |p| p["containerPort"]?.try(&.as_i?) }
      KNOWN.each do |db|
        return {name: db[:name], port: db[:port]} if repo =~ db[:image]
      end
      KNOWN.each do |db|
        return {name: db[:name], port: db[:port]} if ports.includes?(db[:port])
      end
      nil
    end
  end

  module K8s
    # PID of a container on its node, through the cluster-tools pod there;
    # nil when the runtime cannot be asked or does not know the container.
    def self.container_pid(node_name : String, container_id : String) : Int64?
      id = container_id.split("://").last
      inspect = ClusterTools.exec_by_node("crictl inspect #{id}", node_name)
      return nil if inspect.nil? || !inspect[:status].success?
      JSON.parse(inspect[:output]).dig?("info", "pid").try(&.as_i64?)
    rescue JSON::ParseException
      nil
    end

    # One sample of the TCP connections in a container's network namespace,
    # TIME_WAIT ones included, so that short-lived clients are seen too.
    def self.connections(node_name : String, pid : Int64) : Array(Connection)
      netstat = ClusterTools.exec_by_node("nsenter -t #{pid} -n netstat -n", node_name)
      return [] of Connection if netstat.nil?
      Netstat.parse(netstat[:output])
    end
  end
end
