#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'

dest_dir = "_build"
base_dir = "."
verbose = false
to_docx = false
OptionParser.new do |opts|
  opts.banner = %q(Usage: htmlG.rb [options] file -- process single file
Usage: htmlG.rb [options] -- process all markdown and asciidoc files under folder)

  opts.separator ""
  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    verbose = v
  end

  opts.on("-d", "--destination-dir DIR", "destination output directory (default: ./_build)") do |d|
    dest_dir = d.gsub("\\","/")
  end

  opts.on("-b", "--base-dir DIR", "base directory containing files to process (default: .)") do |d|
    base_dir = d.gsub("\\","/")
  end

  opts.on("-w", "--[no-]word", "generate docx instead of html") do |w|
    to_docx = w
  end

  opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
  end
end.parse!

f = ARGV.pop

if not File.directory?(dest_dir) then
    Dir.mkdir(dest_dir)
    if verbose then
        puts "Created destination dir: #{dest_dir}"
    end
end

generate_md = lambda do |file|
    file_ext = File.extname file
    base_name = File.basename file,file_ext
    output_ext = if not to_docx then "html" else "docx" end
    output_file = "#{dest_dir}/#{base_name}.#{output_ext}"

    cmd = if [".md",".markdown"].include?(file_ext) then
             "pandoc -t #{output_ext} -f markdown_github-hard_line_breaks+pandoc_title_block -s -o #{output_file} #{file}"
          elsif [".adoc", ".asciidoc"].include?(file_ext)
              if not to_docx then
                  "asciidoctor -D #{dest_dir} #{file}"
              else
                  "asciidoctor -s -o - #{file} | pandoc -t #{output_ext} -f html -s -o #{output_file}"
              end
          end

    if not cmd then
        puts "Unknown file type: #{file}"
        return
    end

    puts "Executing command: #{cmd}" if verbose
    r = `#{cmd}`
    if r then
        puts r
    end
end

if f then
    generate_md.call f
else
    to_copy = ["_css","_images","_scripts"].select {|d| File.directory? d}
    puts "Copying resources #{to_copy}..." if verbose and to_copy
    to_copy.each do |r|
        FileUtils.cp_r r,dest_dir
    end
        
    files_to_scan = "#{base_dir}/*.{md,markdown,adoc,asciidoc}"
    puts "Processing: #{files_to_scan}..." if verbose
    Dir.glob(files_to_scan) do |path|
        generate_md.call path
    end
end
