require "log"

# Bounded retry for network-bound external fetches: chart pulls, repo adds,
# binary downloads. Every one of these used to be a single attempt, so one
# transient blip from a host we do not control failed a run that said nothing
# about the code under test (#2445).
#
# Only failures that look transient are retried. A missing chart, a 404 or an
# auth error raises immediately: blindly retrying everything would make
# genuine failures take attempts-times longer to report and dress a missing
# chart up as a network problem.
module NetRetry
  Log = ::Log.for("NetRetry")

  ATTEMPTS_ENV = "CNTI_TESTSUITE_NETWORK_RETRY_ATTEMPTS"
  BACKOFF_ENV  = "CNTI_TESTSUITE_NETWORK_RETRY_BACKOFF"

  DEFAULT_ATTEMPTS = 3
  DEFAULT_BACKOFF  = 2

  # For raising a failure that is known to be worth retrying (e.g. an HTTP 5xx,
  # where the status line alone already settles the question).
  class TransientError < Exception
  end

  # What a transient network failure looks like in an error message, across the
  # tools we shell out to (helm, skopeo) and our own HTTP clients: resets,
  # network timeouts, DNS blips, handshake interruptions and server-side 5xx.
  # Deliberately narrow -- "chart not found" or "401" must never match.
  TRANSIENT_PATTERNS = [
    /connection reset/i,
    /connection refused/i,
    /broken pipe/i,
    /\bEOF\b/,
    /i\/o timeout/i,
    /tls handshake/i,
    /deadline exceeded/i,
    /temporary failure/i,
    /no such host/i,
    /name resolution/i,
    /unexpected end of/i,
    /status code: \[5\d\d\]/,
    /internal server error/i,
    /bad gateway/i,
    /service unavailable/i,
    /gateway timeout/i,
  ]

  def self.attempts : Int32
    value = ENV[ATTEMPTS_ENV]?.try(&.to_i?) || DEFAULT_ATTEMPTS
    value < 1 ? 1 : value
  end

  # Base delay in seconds; attempt N waits N * backoff, so the default gives
  # 2s, 4s. Zero disables sleeping (used by specs).
  def self.backoff : Int32
    value = ENV[BACKOFF_ENV]?.try(&.to_i?) || DEFAULT_BACKOFF
    value < 0 ? 0 : value
  end

  # An error is transient when its class says so (our own TransientError,
  # socket/TLS-level errors -- but not File errors, which share IO::Error) or
  # when its message matches a known-transient pattern.
  def self.transient?(ex : Exception) : Bool
    return true if ex.is_a?(TransientError) || ex.is_a?(OpenSSL::Error)
    return true if ex.is_a?(IO::Error) && !ex.is_a?(File::Error)
    message = ex.message
    !message.nil? && TRANSIENT_PATTERNS.any? { |pattern| pattern.match(message) }
  end

  # Runs the block up to `attempts` times. Non-transient errors raise
  # immediately; exhausting the attempts logs how many were made and re-raises
  # the last error.
  def self.with_retries(what : String, logger : ::Log = Log, &)
    attempt = 0
    loop do
      attempt += 1
      begin
        return yield
      rescue ex : Exception
        raise ex unless transient?(ex)
        if attempt >= attempts
          logger.error { "#{what}: giving up after #{attempt} attempt(s): #{ex.message.to_s[0, 300]}" }
          raise ex
        end
        delay = backoff * attempt
        logger.warn { "#{what}: attempt #{attempt}/#{attempts} failed (#{ex.message.to_s[0, 300]}); retrying in #{delay}s" }
        sleep(delay) if delay > 0
      end
    end
  end
end
