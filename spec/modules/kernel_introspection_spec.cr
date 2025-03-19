require "../spec_helper.cr"

describe "KernelInstrospection" do

  it "'#os_release' should get os release info", tags:["kernel_introspection"] do
    release_info = KernelIntrospection.os_release
    (release_info).should_not be_nil
  end
end
