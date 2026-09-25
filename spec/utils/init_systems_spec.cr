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
