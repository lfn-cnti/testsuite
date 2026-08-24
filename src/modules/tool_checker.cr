module ToolChecker
  class Instance
    property path    : String?
    property version : String?

    def initialize(@path : String? = nil, @version : String? = nil); end
  end

  struct Result
    property name     : String
    property global   : Instance
    property local    : Instance
    property warnings : Array(String)
    property errors   : Array(String)

    def initialize(
      @name     : String,
      @global   : Instance = Instance.new,
      @local    : Instance = Instance.new,
      @warnings : Array(String) = [] of String,
      @errors   : Array(String) = [] of String
    ); end

    def global_ok : Bool
      !!(global.path || global.version)
    end

    def local_ok : Bool
      !!(local.path || local.version)
    end

    def ok? : Bool
      errors.empty? && (global_ok || local_ok)
    end
  end

  abstract def tool_name : String
  abstract def global_check(result : Result) : Nil
  abstract def local_check(result  : Result) : Nil
  abstract def post_checks(result  : Result) : Nil

  # run_post_checks: false skips the checks that need more than the binary --
  # Helm's post_checks talks to the cluster, which a presence probe must not.
  def check(run_post_checks : Bool = true) : Result
    result = Result.new(tool_name)

    global_check(result)
    local_check(result)
    post_checks(result) if run_post_checks

    result
  end
end
