require "log"

module KernelIntrospection
  def self.os_release
      Log.info { "KernelIntrospection.os_release" }
    # todo use silent call out
    # os_release = `cat /etc/os-release`
    Process.run(
      # "sudo chmod +x ./clusterctl",
         "cat /etc/os-release",
      shell: true,
      output: stdout = IO::Memory.new,
      error: stderr = IO::Memory.new
    )
    os_release = stdout.to_s
    Log.debug { "os-release: #{os_release}" }
    multiline_os_release = os_release.split("\n")
    parsed_os_release = multiline_os_release.reduce(Hash(String, String).new) do |acc,x|  
      if x.empty? 
        acc 
      else
       acc.merge({"#{x.split("=")[0]}" =>"#{x.split("=")[1]}"})
      end
    end

    if parsed_os_release == Hash(String, String).new
      nil
    else
      parsed_os_release
    end
  end

  def self.os_release_id
    Log.info { "KernelIntrospection.os_release_id" }
    osr = os_release
    if osr 
     id = osr["ID"]
    else
     id =  nil
    end
    Log.info { "os_release: #{osr}" }
    Log.info { "release_id: #{id}" }
    id
  end

  def self.parse_proc(ps_output)
    ps_output.split("\n").map{|x| x.to_i?}.compact
  end

  def self.parse_status(status_output : String) : (Hash(String, String) | Nil) 
    Log.debug { "parse_status status_output: #{status_output}" }
    status = status_output.split("\n").reduce(Hash(String, String).new) do |acc,x| 
      if (x.match(/(.*):(.*)/).try &.[1])
        acc.merge({ "#{(x.match(/(.*):(.*)/).try &.[1])}" => "#{x.match(/(.*):(.*)/).try &.[2]}".strip})
      else
        acc
      end
    end
    if status == Hash(String, String).new
      nil
    else
      status 
    end
  end

  def self.parse_ls(ls : String) : Array(String)
    Log.debug { "parse_ls ls: #{ls}" }
    parsed = ls.strip.split(/[^\S\r]+/).compact
    parsed = parsed.select do |x|
      !x.empty?
    end
    # parsed = ls.strip.split(/[ ]+/)
    Log.debug { "parse_ls parsed: #{parsed}" }
    parsed
  end

  def self.pids_from_ls_proc(ls : Array(String)) : Array(String)
    Log.debug { "pids_from_ls_proc ls: #{ls}" }
    pids = ls.map {|x| "#{x.to_i?}"}.compact
    pids = pids.select do |x|
      !x.empty?
    end
    Log.debug { "pids_from_ls_proc pids: #{pids}" }
    pids
  end

  module Local
    #Exec with Pod Name & Container Name
    #kubectl exec -ti cluster-tools-5tlms --container cluster-tools-two -- cat /proc/1/status
  end

  # todo (optional) get the resource name for the pod name

  # todo get all the pods
  # todo get the pod name
  # todo return all container names in a pod
  # todo loop through all pids in the container 
end
