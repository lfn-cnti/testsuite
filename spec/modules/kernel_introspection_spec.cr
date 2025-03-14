require "../spec_helper"

describe "KernelInstrospection" do

  it "'#os_release' should get os release info", tags: ["kernerl_introspection"] do
    release_info = KernelIntrospection.os_release
    (release_info).should_not be_nil
  end
end
