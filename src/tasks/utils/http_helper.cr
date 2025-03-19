require "colorize"
require "../../modules/kernel_introspection"

module HttpHelper 
  # avoids problems with ssl
  def self.download(url, filename)
    Log.info {"download: #{url}, #{filename}"}

    # if KernelIntrospection.os_release_id =~ /rhel/ ||
    #     KernelIntrospection.os_release_id =~ /centos/
    #     KernelIntrospection.os_release_id =~ /amzn/ 
    #   Log.info {"rhel ssl"}
    #   context = OpenSSL::SSL::Context::Client.insecure
    # else
    #   Log.info {"non-rhel ssl"}
    #   context = OpenSSL::SSL::Context::Client.new 
    # end
    context = context()

    #resp = Halite.follow.get(url, tls: context) do |response|
    #   Log.info {"response status: #{response.status_code}"}
    #   # body = response.body_io.gets_to_end # this is going to be a problem
    #   # Log.info {"response response.body: #{body}"}
    #   File.write(filename, response.body_io)
    # end
    resp = follow(url, filename, context)
    resp 
  end

  def self.download_auth(url, filename)
    Log.info {"download_auth: #{url}, #{filename}"}
    context = context()

    resp = auth(url, filename, context)
    resp 
  end

    def self.context
      Log.info { "KernelIntrospection.os_release_id: #{KernelIntrospection.os_release_id}" }
      if KernelIntrospection.os_release_id =~ /rhel/ ||
          KernelIntrospection.os_release_id =~ /centos/ ||
          KernelIntrospection.os_release_id =~ /fedora/ ||
          KernelIntrospection.os_release_id =~ /amzn/ ||
          KernelIntrospection.os_release_id =~ /rocky/
        context = OpenSSL::SSL::Context::Client.insecure
      else
        context = OpenSSL::SSL::Context::Client.new 
      end
      context
    end

  def self.follow(url, filename, context)
    resp = Halite.follow.get(url, tls: context) do |response|
      Log.info {"response status: #{response.status_code}"}
      # body = response.body_io.gets_to_end # this is going to be a problem
      # Log.info {"response response.body: #{body}"}
      File.write(filename, response.body_io)
    end
    resp
  end

  def self.auth(url, filename, context)
    context = context()
    if ENV.has_key?("GITHUB_TOKEN")
      Halite.auth("Bearer #{ENV["GITHUB_TOKEN"]}").get(url, tls: context) do |response|
        File.write(filename, response.body_io)
      end
    else
      Halite.get(url, tls: context) do |response|
        File.write(filename, response.body_io)
      end
    end
  end
end
