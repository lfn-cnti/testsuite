require "../spec_helper.cr"

describe "Netstat" do
  netstat_output = <<-OUT
  Active Internet connections (w/o servers)
  Proto Recv-Q Send-Q Local Address           Foreign Address         State
  tcp        0      0 10.244.0.193:3306       10.244.0.194:36378      TIME_WAIT
  tcp        0      0 10.244.0.193:3306       10.244.0.195:36680      ESTABLISHED
  tcp6       0      0 ::ffff:10.244.0.193:3306 ::ffff:10.244.0.196:41000 ESTABLISHED
  Active UNIX domain sockets (w/o servers)
  Proto RefCnt Flags       Type       State         I-Node   Path
  unix  3      [ ]         STREAM     CONNECTED     123456   /run/mysqld/mysqld.sock
  OUT

  it "parses the TCP connections and ignores headers and UNIX sockets", tags: ["k8s_netstat"] do
    connections = Netstat.parse(netstat_output)
    connections.size.should eq 3
    connections[0][:foreign_address].should eq "10.244.0.194:36378"
    connections[0][:state].should eq "TIME_WAIT"
    connections[2][:proto].should eq "tcp6"
  end

  it "extracts the IP and port of IPv4 and IPv4-mapped addresses", tags: ["k8s_netstat"] do
    Netstat.address_ip("10.244.0.194:36378").should eq "10.244.0.194"
    Netstat.address_port("10.244.0.194:36378").should eq "36378"
    Netstat.address_ip("::ffff:10.244.0.196:41000").should eq "10.244.0.196"
    Netstat.address_port("::ffff:10.244.0.193:3306").should eq "3306"
  end

  it "recognises databases by image name and by port, and nothing else", tags: ["k8s_netstat"] do
    detect = ->(json : String) { Netstat::Database.detect(JSON.parse(json)) }
    detect.call(%({"name":"mariadb","image":"bitnamilegacy/mariadb:10.6.9-debian-11-r0"})).should eq({name: "MariaDB/MySQL", port: 3306})
    detect.call(%({"name":"db","image":"ghcr.io/org/postgresql@sha256:0123"})).should eq({name: "PostgreSQL", port: 5432})
    detect.call(%({"name":"mongo","image":"mongo:7"})).should eq({name: "MongoDB", port: 27017})
    detect.call(%({"name":"cache","image":"valkey/valkey:8"})).should eq({name: "Redis", port: 6379})
    detect.call(%({"name":"store","image":"my-registry/custom-db:1","ports":[{"containerPort":5432}]})).should eq({name: "PostgreSQL", port: 5432})
    detect.call(%({"name":"exporter","image":"prom/mysqld-exporter:v0.15"})).should be_nil
    detect.call(%({"name":"app","image":"coredns/coredns:1.11","ports":[{"containerPort":53}]})).should be_nil
  end
end
