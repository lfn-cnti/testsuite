require "./utils/utils.cr"
require "./utils/system_information.cr"

module DockerClient
  def self.version_info
    docker_version_info()
  end
  def self.pull(image)
    Log.info { "Docker.pull command: #{image}" }
    status = Process.run("docker pull #{image}",
                         shell: true,
                         output: output = IO::Memory.new,
                         error: stderr = IO::Memory.new)
    Log.info { "Docker.pull output: #{output.to_s}" }
    Log.info { "Docker.pull stderr: #{stderr.to_s}" }
    {status: status, output: output, error: stderr}
  end
  def self.exec(command)
    Log.info { "Docker.exec command: #{command}" }
    status = Process.run("docker exec #{command}",
                         shell: true,
                         output: output = IO::Memory.new,
                         error: stderr = IO::Memory.new)
    Log.info { "Docker.exec output: #{output.to_s}" }
    Log.info { "Docker.exec stderr: #{stderr.to_s}" }
    {status: status, output: output, error: stderr}
  end
  def self.cp(copy)
    Log.info { "Docker.cp command: #{copy}" }
    status = Process.run("docker cp #{copy}",
                         shell: true,
                         output: output = IO::Memory.new,
                         error: stderr = IO::Memory.new)
    Log.info { "Docker.cp output: #{output.to_s}" }
    Log.info { "Docker.cp stderr: #{stderr.to_s}" }
    {status: status, output: output, error: stderr}
  end
  def self.save(image, output_file)
    Log.info { "Docker.save command: docker save #{image} -o #{output_file}" }
    status = Process.run("docker save #{image} -o #{output_file}",
                         shell: true,
                         output: output = IO::Memory.new,
                         error: stderr = IO::Memory.new)
    Log.info { "Docker.save output: #{output.to_s}" }
    Log.info { "Docker.save stderr: #{stderr.to_s}" }
    {status: status, output: output, error: stderr}
  end
  ##############################################
  # All docker images can have one, two, three, or more segments. The docker images that have 
  # multiple segments are separated by a slash.
  #
  # ** Multiple segments **
  # (Fully qualified) registry name with optional port /Org/image combination
  # Multiple segment examples: e.g. docker.io/coredns/coredns
  # mydockerregistry.io:8080/coredns/coredns, mydockerregistry.io:8080/coredns/coredns:latest,	
  # mydockerregistry.io:8080/privatecordnsorg/coredns/coredns:latest
  #
  # Two segment examples: coredns/coredns,
  # 	docker.io/busybox,
  # 	myhostname:5000/myimagename:mytag
  #
  #	1) If the first segment has a period . in it, then the segment is a 
  # fully qualified domain name.
  #
  #	2) If the first segment has colon in it : everything after the colon 
  # is a port number
  #  a) If there are three or more segments, all segments (the middle 
  # segments) from the first and before the last are org names
  #
  # 3) If the first segment is not a fully qualified domain name 
  #  a) if there are two elements, the first element is an org
  #  b) If there are three or more segments, all segments excluding 
  #  the last are org names
  #
  # ** The last segment (or one segment) **
  # Official docker image string
  # e.g. busybox
  #
  # 4.a) If the docker image is only one segment,docker.io is used for the 
  # registry, the whole segment is used image name, and if there is no 
  # tag, `latest` is used as the tag 
  #
  # 4.b) Everything in the one segment (or the last segment if there are 
  # multiple segments) is an image or image:tag combination.
  # ```
  # DockerClient.parse_image("mydockerregistry.io:8080/coredns/coredns:latest") 
  # # => {"org_image" => "coredns/corends:latest", "org" => "coredns", 
  # # "image" => "coredns:latest", "registry" => "mydockerregistry.io:8080", "tag" => "latest"}
  # ```
  def self.parse_image(fqdn_image_text : String)
    resp = {"registry" => "", 
            "org_image" => "",
            "org" => "", 
            "image_and_tag" => "", 
            "image_name" => "", 
            "tag" => "",
           "complete_fqdn" => ""}
    size = fqdn_image_text.split("/").size 
    first_segment = fqdn_image_text.split("/")[0]
    last_segment = fqdn_image_text.split("/")[-1]

    #	1) If the first segment has a period . in it, then the segment is a 
    # fully qualified domain name.
    #	2) If the first segment has colon in it : everything after the colon 
    # is a port number
    # todo write a test for 88-111
    if (first_segment =~ /\./ || first_segment =~ /:/)
      resp["registry"] = first_segment 
      #  a) If there are three or more segments, all segments (the middle 
      # segments) from the first and before the last are org names
      if size > 2
        resp["org"] = fqdn_image_text.split("/")[1..-2].join("/")
      elsif size = 2
        resp["org"] = first_segment
      else
        Log.error {"size of image text should never = 1 or nil: #{fqdn_image_text}"}
      end
    else # first segment not a registry
      resp["registry"] = ""
      if size = 1
        resp["org"] = ""
        # 3) If the first segment is not a fully qualified domain name 
        #  a) if there are two segments, the first segment is an org
      elsif size = 2
        resp["org"] = first_segment
        #  b) If there are three or more segments, all segments (the middle 
        # segments) after the first and before the last are org names
      elsif size > 2
        resp["org"] = fqdn_image_text.split("/")[0..-2].join("/")
      end
    end
    # resp["org_image"] = "#{resp["org"].empty? ? "" : resp["org"] + "/"}#{last_segment}"
    # 4.a) If there is only one segment, docker.io is used for the 
    # registry.  If there is no : in the image text, `latest` is used as the tag 
    # 4.b) Everything in the one segment (or the last segment if there are 
    # multiple segments) is an image or image:tag combination.
    resp["image_and_tag"] = last_segment
    if size == 1 
        resp["registry"] = "docker.io"
    end
    if resp["registry"].empty?
      resp["org_image"] = fqdn_image_text
      resp["complete_fqdn"] = resp["org_image"]
    else
      resp["org_image"] = fqdn_image_text
      resp["complete_fqdn"] = resp["registry"] + "/" + resp["org_image"]
    end

    resp["image_name"] = last_segment.split(":")[0]? || ""
    if last_segment.split(":")[1]?
        resp["tag"] = last_segment.split(":")[1]? || ""
    else
        resp["tag"] = "latest"
    end
    Log.info { "org/image:tag : #{resp}" }
    resp
	end

  module Get
    
    def self.image_by_tag(docker_image_list, tag)
      # if image_tag = nil then get latest tag
      modified_tag = tag == nil ? "latest" : tag
      latest_image = docker_image_list.parse("json")["results"].as_a.find{|x|x["name"]=="#{modified_tag}"} 
      Log.debug { "docker parse resp: #{latest_image}" }
      (Log.error{"no image found for tag: #{modified_tag}"}) if latest_image == nil
      latest_image 
    end
  end

  def self.named_sha_list(resp_json)
    Log.debug { "sha_list resp_json: #{resp_json}" }
    parsed_json = JSON.parse(resp_json)
    Log.debug { "sha list parsed json: #{parsed_json}" }
    #if tags then this is a quay repository, otherwise assume docker hub repository
    if parsed_json["tags"]?
        parsed_json["tags"].not_nil!.as_a.reduce([] of Hash(String, String)) do |acc, i|
      acc << {"name" => i["name"].not_nil!.as_s, "manifest_digest" => i["manifest_digest"].not_nil!.as_s}
    end
    else
      parsed_json["results"].not_nil!.as_a.reduce([] of Hash(String, String)) do |acc, i|
        # always use amd64
        amd64image = i["images"].as_a.find{|x| x["architecture"].as_s == "amd64"}
        Log.debug { "amd64image: #{amd64image}" }
        if amd64image && amd64image["digest"]?
            acc << {"name" => i["name"].not_nil!.as_s, "manifest_digest" => amd64image["digest"].not_nil!.as_s}
        else
          Log.error { "amd64 image not found in #{i["images"]}" }
          acc
        end
      end
    end
  end

  module K8s
    def self.local_digest_match(remote_sha_list, local_digests)
      Log.info { "remote_sha_list: #{ remote_sha_list}"}
      # Log.info { "remote_sha_list: #{ remote_sha_list.map { |x| x && x["manifest_digest"] }}"}
 
      # find hash for image
      Log.info { "local_digests: #{local_digests}" }
      found = false
      release_name = ""
      digest = ""
      remote_sha_list.each do |x|
        if local_digests.find{|i| i.includes?(x["manifest_digest"])}
          found = true
          release_name = x["name"]
          digest = x["manifest_digest"]
        end
      end
      {found: found, digest: digest, release_name: release_name}
    end
  end
end
