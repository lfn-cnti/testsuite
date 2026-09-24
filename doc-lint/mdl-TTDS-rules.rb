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
          unless text == "Table of Contents" || text.start_with?("Category:")
            violation_lines << line_number
          end
        when 4
          allowed_texts = ["Overview", "Rationale", "Remediation", "Usage"]
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
    current_test_header = nil
    found_subsections = []
    parsed.root.children.each do |element|
      if element.type == :header
        if element.options[:level] == 3 && element.options[:raw_text] != "Usage"
          unless found_subsections.sort == required_subsections.sort || current_test_header.nil?
            violation_lines << current_test_header.options[:location]
          end
          current_test_header = element
          found_subsections = []
        elsif element.options[:level] == 4
          found_subsections << element.options[:raw_text]
        end
      end
    end
    unless found_subsections.sort == required_subsections.sort
      violation_lines << current_test_header.options[:location]
    end
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
