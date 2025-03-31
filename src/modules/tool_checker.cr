module ToolChecker
  abstract def tool_name : String
  abstract def global_check : Bool
  abstract def local_check : Bool
  abstract def post_checks : Bool

  def installation_found? : Bool
    found = global_check || local_check
    stdout_success "#{tool_name} found" if found
    return false unless found

    post_checks
  end
end