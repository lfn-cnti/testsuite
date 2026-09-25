require "../spec_helper"

describe "InitSystems.init_cmd_from_cmdline" do
  it "takes the executable from a NUL-separated command line", tags: ["points"] do
    InitSystems.init_cmd_from_cmdline("/package/admin/s6/command/s6-svscan\u0000-d4\u0000--\u0000/run/service\u0000").should eq("/package/admin/s6/command/s6-svscan")
    InitSystems.init_cmd_from_cmdline("/sbin/tini\u0000--\u0000app\u0000").should eq("/sbin/tini")
  end

  it "does not take an empty read for an init process", tags: ["points"] do
    InitSystems.init_cmd_from_cmdline("").should be_nil
    InitSystems.init_cmd_from_cmdline("\n").should be_nil
    InitSystems.init_cmd_from_cmdline("\u0000").should be_nil
  end
end
