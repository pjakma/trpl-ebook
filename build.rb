#! env ruby

# The date of the src/ files
RELEASE_DATE = "2015-05-15"

TOC_LINK_REGEX = /(?<indent>\s*?)\* \[(?<title>.+?)\]\((?<filename>.+?)\)/

HIDDEN_CODE = Regexp.new("^# ")
RUST_CODE_START = Regexp.new("^```(.*)rust(.*)")
CODE_BLOCK_START = CODE_BLOCK_END = Regexp.new("^```")

MARKDOWN_OPTIONS = "markdown+grid_tables+pipe_tables+raw_html+implicit_figures+footnotes+intraword_underscores+auto_identifiers-inline_code_attributes"

def break_long_lines(line, max_len=87, sep="↳ ")
    return line if line.length <= max_len

    output = ""

    cursor = max_len
    output << line[0..cursor - 1]
    while line.length > cursor
        new_cursor = cursor + (max_len - sep.length)
        output << "\n"
        output << sep
        output << line[cursor..new_cursor - 1]
        cursor = new_cursor
    end
    output
end

def break_long_code_lines(input)
    in_code_block = false

    input
    .lines.reduce "" do |initial, line|
        if in_code_block && line.match(CODE_BLOCK_END)
            in_code_block = false
            initial + line
        elsif in_code_block
            initial + break_long_lines(line)
        elsif line.match(CODE_BLOCK_START)
            in_code_block = true
            initial + line
        else
            initial + line
        end
    end
end

def normalizeCodeSnipetts(input)
    in_code_block = false

    input
    .lines.reduce "" do |initial, line|
        if in_code_block and line.match(HIDDEN_CODE)
            # skip line
            initial
        elsif line.match(RUST_CODE_START)
            in_code_block = true
            # normalize code block start
            initial + "```rust\n"
        elsif line.match(CODE_BLOCK_END)
            in_code_block = false
            initial + "```\n"
        else
            initial + line
        end
    end
end

def normalize_title(title)
    # Some chapter titles start with Roman numerals, e.g. "I: The Basics"
    title.sub /(([IV]+):\s)/, ''
end

def normalizeLinks(input)
    input
    .gsub("../std", "http://doc.rust-lang.org/std")
    .gsub("../reference", "http://doc.rust-lang.org/reference")
    .gsub("../rustc", "http://doc.rust-lang.org/rustc")
    .gsub("../syntax", "http://doc.rust-lang.org/syntax")
    .gsub("../core", "http://doc.rust-lang.org/core")
    .gsub(/\]\(([\w\-\_]+)\.html\)/, '](#sec--\1)') # internal links: each file begins with <hX id="#sec-FILEANME">TITLE</hX>
end

def pandoc(file, header_level=3)
    normalizeTables = 'sed -E \'s/^\+-([+-]+)-\+$/| \1 |/\''

    normalizeCodeSnipetts normalizeLinks `cat #{file} | #{normalizeTables} | pandoc --from=#{MARKDOWN_OPTIONS} --to=#{MARKDOWN_OPTIONS} --base-header-level=#{header_level} --indented-code-classes=rust --atx-headers`
end

book = <<-eos
---
title: "The Rust Programming Language"
author: "The Rust Team"
date: #{RELEASE_DATE}
description: "This book will teach you about the Rust Programming Language. Rust is a modern systems programming language focusing on safety and speed. It accomplishes these goals by being memory safe without using garbage collection."
language: en
documentclass: book
links-as-notes: true
verbatim-in-note: true
toc-depth: 2
...

eos

book << "# Introduction\n\n"
book << pandoc("src/README.md", 1)
book << "\n\n"

File.open("src/SUMMARY.md", "r").each_line do |line|
    link = TOC_LINK_REGEX.match(line)
    if link
        level = link[:indent].length == 0 ? "#" : "##"
        book << "#{level} #{normalize_title link[:title]} {#sec--#{File.basename(link[:filename], '.*')}}\n\n"
        book << pandoc("src/#{link[:filename]}")
        book << "\n\n"
    end
end

File.open("dist/trpl-#{RELEASE_DATE}.md", "w") { |file|
    file.write(book)
    puts "[✓] Markdown"
}

`pandoc dist/trpl-#{RELEASE_DATE}.md --from=#{MARKDOWN_OPTIONS} --smart --normalize --standalone --self-contained --highlight-style=tango --table-of-contents --template=lib/template.html --css=lib/pandoc.css --to=html5 --output=dist/trpl-#{RELEASE_DATE}.html`
puts "[✓] HTML"

`pandoc dist/trpl-#{RELEASE_DATE}.md --from=#{MARKDOWN_OPTIONS} --smart --normalize --standalone --self-contained --highlight-style=tango --epub-stylesheet=lib/epub.css --table-of-contents --output=dist/trpl-#{RELEASE_DATE}.epub`
puts "[✓] EPUB"

# again, with shorter code lines
File.open("dist/trpl-#{RELEASE_DATE}.md", "w") { |file|
    file.write(break_long_code_lines(book))
    puts "[✓] Markdown"
}
`pandoc dist/trpl-#{RELEASE_DATE}.md --from=#{MARKDOWN_OPTIONS} --smart --normalize --standalone --self-contained --highlight-style=tango --chapters --table-of-contents --variable papersize='a4paper' --variable monofont='DejaVu Sans Mono' --template=lib/template.tex --latex-engine=xelatex --to=latex --output=dist/trpl-#{RELEASE_DATE}-a4.pdf`
puts "[✓] PDF (A4)"

`pandoc dist/trpl-#{RELEASE_DATE}.md --from=#{MARKDOWN_OPTIONS} --smart --normalize --standalone --self-contained --highlight-style=tango --chapters --table-of-contents --variable monofont='DejaVu Sans Mono' --variable papersize='letterpaper' --template=lib/template.tex --latex-engine=xelatex --to=latex --output=dist/trpl-#{RELEASE_DATE}-letter.pdf`
puts "[✓] PDF (Letter)"

# back to original line length
File.open("dist/trpl-#{RELEASE_DATE}.md", "w") { |file|
    file.write(book)
    puts "[✓] Markdown"
}

FILE_PREFIX = /^trpl-(?<date>(\d+)-(\d+)-(\d+))/
FILE_NAME = /^trpl-(?<date>(\d+)-(\d+)-(\d+))(?<name>.*)/

file_listing = Dir["dist/trpl*"]
    .map{|f| f.gsub("dist/", "") }
    .sort.reverse
    .group_by {|f| f[FILE_PREFIX] }
    .reject
    .map {|prefix, files|
        html = "<li><h2>#{prefix.match(FILE_PREFIX)[:date]}</h2><ul>"
        html << files.map {|file|
            "<li><a href='#{file}'>#{
                file.match(FILE_NAME)[:name].gsub('-', '').gsub('.', ' ').upcase
            }</a></li>"
        }.join("\n")
        html << "</ul></li>"
        html
    }.join("\n")

index = <<-eos
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Download 'The Rust Programming Language'</title>
    <style>
        body { max-width: 32em; margin: 10em auto; font-size: 16px; font-family: sans-serif; line-height: 1.3; }
        li { margin-bottom: 0.5em; }
    </style>
</head>
<body>
    <h1>The Rust Programming Language</h1>
    <ul>
        <li>
            <strong><a href="http://doc.rust-lang.org/book/">The original on rust-lang.org</a></strong>
        </li>
        #{file_listing}
    </ul>
    <a href="https://github.com/killercup/trpl-ebook">
        <img style="position: absolute; top: 0; right: 0; border: 0;" src="https://s3.amazonaws.com/github/ribbons/forkme_right_gray_6d6d6d.png" alt="Fork me on GitHub"/>
      </a>
</body>
</html>
eos

File.open("dist/index.html", "w") { |file|
    file.write(index)
    puts "[✓] Index page"
}