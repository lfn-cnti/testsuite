require "../spec_helper"

# The recognised container init systems, by the executable's basename.
describe "InitSystems.is_specialized_init_system?" do
  it "recognises the purpose-built container inits, gopherd included", tags: ["points"] do
    ["/sbin/tini", "/usr/bin/dumb-init", "/usr/bin/catatonit", "/package/admin/s6/command/s6-svscan", "/usr/local/sbin/gopherd"].each do |cmd|
      InitSystems.is_specialized_init_system?(cmd).should be_true
    end
  end

  it "does not recognise an application binary or a shell as an init", tags: ["points"] do
    ["/usr/sbin/nginx", "/bin/bash", "/coredns", "/usr/local/bin/traefik"].each do |cmd|
      InitSystems.is_specialized_init_system?(cmd).should be_false
    end
  end
end

# Inits that boot a whole operating system, by the executable PID 1 runs (#2886).
describe "InitSystems.system_init?" do
  it "recognises systemd, SysV, upstart and BusyBox init, OpenRC and runit", tags: ["points"] do
    ["/usr/lib/systemd/systemd", "/lib/systemd/systemd", "/sbin/init", "/bin/init", "/sbin/openrc-init", "/sbin/runit-init", "/sbin/runit"].each do |exe|
      InitSystems.system_init?(exe).should be_true
    end
  end

  it "recognises BusyBox only when its applet is init", tags: ["points"] do
    InitSystems.system_init?("/bin/busybox", "init").should be_true
    InitSystems.system_init?("/bin/busybox", "sh").should be_false
    InitSystems.system_init?("/bin/busybox").should be_false
  end

  it "reads BusyBox's applet from the name it was started under, else from its first argument", tags: ["points"] do
    # Alpine's /sbin/init, a symlink to busybox.
    InitSystems.busybox_applet("init\n", "/sbin/init\u0000").should eq("init")
    # Started as busybox itself.
    InitSystems.busybox_applet("busybox\n", "/bin/busybox\u0000init\u0000").should eq("init")
    InitSystems.busybox_applet("busybox\n", "/bin/busybox\u0000sh\u0000-c\u0000sleep 1\u0000").should eq("sh")
    InitSystems.busybox_applet("busybox\n", "/bin/busybox\u0000").should eq("")
  end

  it "does not take a container init, a shell or an application for one", tags: ["points"] do
    ["/sbin/tini", "/usr/bin/dumb-init", "/package/admin/s6/command/s6-svscan", "/bin/sh", "/usr/bin/dash", "/coredns", "/usr/sbin/nginx", "/usr/sbin/initctl"].each do |exe|
      InitSystems.system_init?(exe).should be_false
    end
  end
end

describe "InitSystems.exe_from_link" do
  it "reads the path of /proc/<pid>/exe, without the mark of a replaced file", tags: ["points"] do
    InitSystems.exe_from_link("/usr/lib/systemd/systemd\n").should eq("/usr/lib/systemd/systemd")
    InitSystems.exe_from_link("/usr/sbin/nginx (deleted)\n").should eq("/usr/sbin/nginx")
    InitSystems.exe_from_link(" \n").should be_nil
  end
end
