require "sam"

# In-repo fixes for the vendored SAM argument parser (vulk/sam.cr, pinned by
# commit in shard.yml). lib/ is not part of this repository, so the parser
# methods are reopened here; drop this file if the fixes land upstream.
class Sam::Args
  # Upstream crashes with IndexError on an empty argument.
  private def option_name(str)
    return nil if str.empty?
    if str[0] == '-'
      str[1..-1]
    elsif str =~ /=/
      str.split("=", 2)[0]
    end
  end

  # Upstream splits on every "=", truncating values that contain one
  # (e.g. cnf-config=path=with=equals ended up as just "path").
  private def option_value(str : String, same_string = true)
    return nil if str.empty?
    if same_string
      if str =~ /=/
        str.split("=", 2)[1]
      elsif str[0] != '-'
        str
      end
    elsif str[0] != '-' && !(str =~ /=/)
      str
    end
  end
end
