require "../spec_helper"
require "http/server"

# In-process: exercises the wrapper and download_file directly, with backoff
# zeroed so exhaustion paths stay fast.
private def without_backoff(&)
  ENV[NetRetry::BACKOFF_ENV] = "0"
  yield
ensure
  ENV.delete(NetRetry::BACKOFF_ENV)
  ENV.delete(NetRetry::ATTEMPTS_ENV)
end

private def serve(&handler : HTTP::Server::Context, Int32 -> Nil) : {HTTP::Server, String}
  hits = 0
  server = HTTP::Server.new do |context|
    hits += 1
    handler.call(context, hits)
  end
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  Fiber.yield
  {server, "http://#{address}"}
end

describe "NetRetry" do
  it "classifies transient and permanent failures", tags: ["points"] do
    ["connection reset by peer", "dial tcp: lookup x: i/o timeout", "unexpected EOF",
     "TLS handshake timeout", "Temporary failure in name resolution",
     "Unsuccessful request, status code: [503], msg: Service Unavailable",
     "server responded with 502 Bad Gateway"].each do |message|
      NetRetry.transient?(Exception.new(message)).should be_true
    end

    ["chart \"nope\" not found in https://example.com repository",
     "401 Unauthorized", "Error: INSTALLATION FAILED: values don't meet the specifications",
     "Unsuccessful request, status code: [404], msg: Not Found"].each do |message|
      NetRetry.transient?(Exception.new(message)).should be_false
    end

    NetRetry.transient?(NetRetry::TransientError.new("anything")).should be_true
    NetRetry.transient?(IO::TimeoutError.new("read timed out")).should be_true
    NetRetry.transient?(File::NotFoundError.new("gone", file: "gone")).should be_false
  end

  it "retries transient failures up to the configured attempts and re-raises", tags: ["points"] do
    without_backoff do
      ENV[NetRetry::ATTEMPTS_ENV] = "3"

      calls = 0
      result = NetRetry.with_retries("flaky") do
        calls += 1
        raise NetRetry::TransientError.new("blip") if calls < 3
        "recovered"
      end
      result.should eq("recovered")
      calls.should eq(3)

      calls = 0
      expect_raises(NetRetry::TransientError) do
        NetRetry.with_retries("hopeless") do
          calls += 1
          raise NetRetry::TransientError.new("still down")
        end
      end
      calls.should eq(3)
    end
  end

  it "does not retry a permanent failure", tags: ["points"] do
    without_backoff do
      calls = 0
      expect_raises(Exception, "not found") do
        NetRetry.with_retries("permanent") do
          calls += 1
          raise "chart not found"
        end
      end
      calls.should eq(1)
    end
  end

  it "download_file absorbs a 5xx blip but fails a 404 immediately", tags: ["points"] do
    without_backoff do
      output = File.tempname("net-retry", ".bin")

      server, url = serve do |context, hits|
        if hits < 3
          context.response.status_code = 503
        else
          context.response.print "payload"
        end
      end
      begin
        download_file(url, output)
        File.read(output).should eq("payload")
      ensure
        server.close
        File.delete?(output)
      end

      server, url = serve do |context, hits|
        context.response.status_code = 404
      end
      begin
        requests = 0
        expect_raises(Exception, "status code: [404]") { download_file(url, output) }
        File.exists?(output).should be_false
      ensure
        server.close
        File.delete?(output)
      end
    end
  end
end
