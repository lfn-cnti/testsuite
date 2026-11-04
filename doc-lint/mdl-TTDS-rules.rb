# TTDS stands for Testsuite Test Documentation Style
rule "TTDS001", "Testsuite documentation header format" do
  tags :documentation
  check do |doc|
    parsed = doc.parsed
    violation_lines = []
    parsed.root.children.each do |element|
      if element.type == :header
        text = element.options[:raw_text]
        line_number = element.options[:location]
        case element.options[:level]
        when 2
          unless ["Table of Contents", "Test types", "Common rules"].include?(text) || text.start_with?("Category:")
            violation_lines << line_number
          end
        when 4
          allowed_texts = ["Overview", "Rationale", "Remediation", "Usage", "Details"]
          unless allowed_texts.include?(text)
            violation_lines << line_number
          end
        end
      end
    end
    violation_lines.empty? ? nil : violation_lines
  end
end

rule "TTDS002", "All categories and tests are present in TOC" do
  tags :documentation
  check do |doc|
    toc_regex = /## Table of Contents\n\n[\s\S]*?\n## /m
    doc_text = doc.lines.join("\n")
    toc_text = doc_text.scan(toc_regex).first
    parsed = doc.parsed
    violation_lines = []
    if toc_text.nil?
      puts "Table of Contents not found"
      violation_lines << 1
    end
    parsed.root.children.each do |element|
      if element.type == :header
        text = element.options[:raw_text]
        line_number = element.options[:location]
        case element.options[:level]
        when 2
          unless toc_text.include?(text)
            violation_lines << line_number
          end
        when 3
          unless text == "Usage" || toc_text.include?(text)
            violation_lines << line_number
          end
        end
      end
    end
    violation_lines.empty? ? nil : violation_lines
  end
end

rule "TTDS003", "Separators before tests and categories are present" do
 tags :documentation
 check do |doc|
    parsed = doc.parsed
    violation_lines = []
    parsed.root.children.each do |element|
      if element.type == :header
        text = element.options[:raw_text]
        line_number = element.options[:location]
        case element.options[:level]
        when 2, 3
          unless text == "Table of Contents" || text == "Usage"
            separator_line_number = line_number - 3
            separator_line = doc.lines[separator_line_number.clamp(0, doc.lines.length - 1)]
            unless separator_line.strip =~ /---/
              violation_lines << line_number
            end
          end
        end
      end
    end
    violation_lines.empty? ? nil : violation_lines
  end
end

rule "TTDS004", "Tests should have all required sub-sections" do
 tags :documentation
 check do |doc|
    parsed = doc.parsed
    violation_lines = []
    required_subsections = ["Overview", "Rationale", "Remediation", "Usage"]
    optional_subsections = ["Details"]
    current_test_header = nil
    found_subsections = []
    in_common_rules = false
    close = lambda do
      next if current_test_header.nil?
      unless (found_subsections - optional_subsections).sort == required_subsections.sort
        violation_lines << current_test_header.options[:location]
      end
    end
    parsed.root.children.each do |element|
      next unless element.type == :header
      case element.options[:level]
      when 2
        # The sections under "Common rules" are shared rules, not tests.
        close.call
        current_test_header = nil
        in_common_rules = element.options[:raw_text] == "Common rules"
      when 3
        next if element.options[:raw_text] == "Usage"
        close.call
        current_test_header = in_common_rules ? nil : element
        found_subsections = []
      when 4
        found_subsections << element.options[:raw_text]
      end
    end
    close.call
    violation_lines.empty? ? nil : violation_lines
  end
end

rule "TTDS005", "TOC should not contain non-existent tests" do
  tags :documentation
  check do |doc|
    toc_regex = /## Table of Contents\n\n[\s\S]*?\n## /m
    doc_text = doc.lines.join("\n")
    toc_text = doc_text.scan(toc_regex).first
    parsed = doc.parsed
    violation_lines = []
    test_header_names = []
    if toc_text.nil?
      puts "Table of Contents not found"
      violation_lines << 1
    end
    parsed.root.children.each do |element|
      if element.type == :header
        text = element.options[:raw_text]
        line_number = element.options[:location]
        if element.options[:level] == 3 && text != "Usage"
          test_header_names << text.strip
        end
      end
    end
    toc_header_names = toc_text.scan(/\[\[([^\]]*)\]\]/).flatten
    toc_header_names.each do |toc_header_name|
      unless test_header_names.include?(toc_header_name)
        violation_lines << 1
      end
    end
    violation_lines.empty? ? nil : violation_lines
  end
end

rule "TTDS006", "TOC should not contain 'dead' local links" do
  tags :documentation
  check do |doc|
    parsed = doc.parsed
    violation_lines = []
    headers = Set[]
    parsed.root.children.each do |element|
      if element.type == :header
        headers.add(element.options[:raw_text].downcase.delete('^a-z0-9\- ').tr(' ', '-'))
      end
    end
    link_regex = /\[.*?\]\(#(.*?)\)/
    doc.lines.each_with_index do |line, line_number|
      match = line.scan(link_regex).flatten
      if match
        match.each do |link|
          unless headers.include?(link)
            violation_lines << line_number + 1
            puts "Dead link: #{link}"
          end
        end

      end
    end
    violation_lines.empty? ? nil : violation_lines
  end
end

rule "TTDS007", "Every Rationale names the source of the practice (at least one external link)" do
  tags :documentation
  check do |doc|
    violation_lines = []
    in_rationale = false
    rationale_line = nil
    has_link = false
    close = lambda do
      violation_lines << rationale_line if in_rationale && !has_link
    end
    doc.lines.each_with_index do |line, index|
      if line.start_with?("#### Rationale")
        close.call
        in_rationale = true
        rationale_line = index + 1
        has_link = false
      elsif line.start_with?("#### ") || line.start_with?("### ")
        close.call
        in_rationale = false
      elsif in_rationale && line =~ /\]\(https?:\/\//
        has_link = true
      end
    end
    close.call
    violation_lines.empty? ? nil : violation_lines
  end
end

# A test whose behaviour is written out under Details keeps its Overview brief:
# what it checks, for a person reading the page. Applies to the tests with a
# Details section, which are being moved there (#2888).
OVERVIEW_WORD_LIMIT = 60

rule "TTDS008", "An Overview stays within #{OVERVIEW_WORD_LIMIT} words, its Expectation line apart, when the test has Details" do
  tags :documentation
  check do |doc|
    violation_lines = []
    sections = []
    doc.lines.each_with_index do |line, index|
      if line.start_with?("### ")
        sections << {overview_line: nil, words: 0, details: false, in_overview: false}
      elsif (section = sections.last)
        if line.start_with?("#### ")
          section[:in_overview] = line.strip == "#### Overview"
          section[:overview_line] = index + 1 if section[:in_overview]
          section[:details] = true if line.strip == "#### Details"
        elsif section[:in_overview] && !line.start_with?("Expectation:")
          section[:words] += line.split.size
        end
      end
    end
    sections.each do |section|
      if section[:details] && section[:overview_line] && section[:words] > OVERVIEW_WORD_LIMIT
        violation_lines << section[:overview_line]
      end
    end
    violation_lines.empty? ? nil : violation_lines
  end
end

DETAILS_LABELS = ["Scope", "Configuration", "Verdicts", "Side effects", "Limits", "Common rules"]

rule "TTDS009", "Details is a collapsed list whose items start with one of #{DETAILS_LABELS.join(", ")}" do
  tags :documentation
  check do |doc|
    violation_lines = []
    in_details = false
    details_line = nil
    items = 0
    # :before the <details> tag, :open inside it, :closed after </details>.
    state = :before
    previous = ""
    close = lambda do
      violation_lines << details_line if in_details && (items.zero? || state != :closed)
    end
    doc.lines.each_with_index do |line, index|
      if line.strip == "#### Details"
        close.call
        in_details = true
        details_line = index + 1
        items = 0
        state = :before
      elsif line.start_with?("#### ") || line.start_with?("### ") || line.start_with?("## ") || line.strip == "----------"
        close.call
        in_details = false
      elsif in_details
        if line.strip == "<details>"
          state = state == :before ? :open : :closed_twice
        elsif line.strip == "</details>"
          state = state == :open ? :closed : :closed_twice
        elsif line.start_with?("* ")
          # Only inside the collapsed block, and only under the fixed labels.
          # The first item follows a blank line: without one, GitHub keeps
          # the list in the HTML block and shows it as plain text.
          label = line[/\A\* \*\*([^*]+)\*\*:/, 1]
          if state == :open && label && DETAILS_LABELS.include?(label) && (items > 0 || previous.strip.empty?)
            items += 1
          else
            violation_lines << index + 1
          end
        end
      end
      previous = line
    end
    close.call
    violation_lines.empty? ? nil : violation_lines
  end
end

# Details is a raw HTML block: kramdown reads a <placeholder> in it as an HTML
# tag even inside backticks, and every heading after it drops out of the
# parse (and out of TTDS002/TTDS005). Placeholders there are written in
# capitals, as in /proc/PID/status.
rule "TTDS010", "No <placeholder> in angle brackets inside Details" do
  tags :documentation
  check do |doc|
    violation_lines = []
    in_details = false
    doc.lines.each_with_index do |line, index|
      if line.strip == "<details>"
        in_details = true
      elsif line.strip == "</details>"
        in_details = false
      elsif in_details && line.gsub(%r{</?(details|summary)>}, "") =~ /<\/?[a-zA-Z][^<>]*>/
        violation_lines << index + 1
      end
    end
    violation_lines.empty? ? nil : violation_lines
  end
end
