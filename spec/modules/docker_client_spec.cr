require "../spec_helper.cr"

describe "DockerClient" do
  it "'installation_found?' should show a git client was located", tags:["docker_client"] do
    (DockerClient.pull("hello-world")[:output].to_s).should contain("Pulling from")
  end

  it "'docker_version_info()' should return the information about the docker installation", tags:["docker_client"] do
    docker_version = DockerClient.version_info()
    typeof(docker_version).should eq(DockerVersion)
    typeof(docker_version.installed?).should eq(Bool)
  end

  it "'docker_global_response()' should return the information about the docker installation", tags:["docker_client"] do
    (docker_global_response(true)).should contain("docker-init")
  end

  it "'docker_local_response()' should return the information about the docker installation", tags:["docker_client"] do
    (docker_local_response(true)).should eq("") 
  end

  it "'parse_docker_version()' should return the information about the docker version", tags:["docker_client"] do
    (parse_docker_version(docker_global_response)).should match(/(([0-9]{1,3}[\.]){1,2}[0-9]{1,3})/)
    (parse_docker_version(docker_local_response)).should contain("")
  end

  it "'docker_version_info()' should return the information about the docker installation", tags:["docker_client"] do
    docker_version = docker_version_info()
    typeof(docker_version).should eq(DockerVersion)
    typeof(docker_version.installed?).should eq(Bool)
  end
end
