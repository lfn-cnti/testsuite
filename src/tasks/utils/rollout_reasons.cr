def report_unconfigured_release(result, label : String, reason : String?, unconfigured_reasons : Set(String)) : Nil
  text = reason ? "#{label}: #{reason}" : "#{label} has no previous release"
  unconfigured_reasons << text
  result.append_description("#{text}; not judged")
end
