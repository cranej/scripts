#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'

dest_dir = "_build"
base_dir = "."
verbose = false
to_docx = false
# I prefer not to load google web fonts and Awesome Fount by default.
# Also disable footer
adoc_opts = "-a iconfont-remote! -a webfonts! -a nofooter"
pandoc_opts = ""
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

  opts.on("--adoc-opts OPTIONS", 
          "add more options for underlying asciidoc processor 'asciidoctor'",
          " can be used to overwrite default attributes or options.",
          " Must be quoted if has spaces like \"-a noheader -a webfont\"") do |aopts|
    adoc_opts = "#{adoc_opts} #{aopts}"
  end

  opts.on("--pandoc-opts OPTIONS",
          "add more options for underlying markdown processor 'pandoc'",
          " can be used to overwrite default options.",
          " Must be quoted if has spaces like \"--toc -S\"") do |popts|
    pandoc_opts = "#{pandoc_opts} #{popts}"
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

generate_md = lambda do |finfo|
    (file, base_name, file_ext) = finfo
    output_ext = if not to_docx then "html" else "docx" end
    output_file = "#{dest_dir}/#{base_name}.#{output_ext}"

    cmd = if [".md",".markdown"].include?(file_ext) then
             "pandoc -t #{output_ext} -f markdown_github-hard_line_breaks+pandoc_title_block #{pandoc_opts} -s -o #{output_file} #{file}"
          elsif [".adoc", ".asciidoc"].include?(file_ext)
              asciidoctor_cmd = "asciidoctor #{adoc_opts} "
              if not to_docx then
                  "#{asciidoctor_cmd} -D #{dest_dir} #{file}"
              else
                  "#{asciidoctor_cmd} -o - #{file} | pandoc -t #{output_ext} -f html -s -o #{output_file}"
              end
          end

    if not cmd then
        puts "Unknown file type: #{file}"
        return
    end

    puts "Executing command: #{cmd}" if verbose
    r = `#{cmd}`
    if r and r!="" then
        puts r
    end
end

def file_info(f)
    file_ext = File.extname f
    base_name = File.basename f,file_ext
    [f, base_name, file_ext, File.mtime(f).strftime("%F")]
end

puts "assciidoctor options: #{adoc_opts}" if verbose
puts "pandoc options: #{pandoc_opts}" if verbose

if f then
    generate_md.call(file_info(f))
else
    to_copy = ["#{base_dir}/_css","#{base_dir}/_images","#{base_dir}/_scripts"].select {|d| File.directory? d}
    puts "Copying resources #{to_copy}..." if verbose and to_copy
    to_copy.each do |r|
        FileUtils.cp_r r,dest_dir
    end
        
    files_to_scan = "#{base_dir}/*.{md,markdown,adoc,asciidoc}"
    puts "Processing: #{files_to_scan}..." if verbose

    index_item_tpl = %{
        <li>
            <a class="item-link" href="@item-href">@item-title</a>
        </li>}
    index_page_tpl = %{
        <!DOCTYPE html>
        <html>
        <head>
            <title>Index</title>
            <style>
            .page-content \{
                padding: 30px 0;
                font-size: 16px;
                line-height:1.5;
                color: #111;
            \}
            .wrapper \{
                max-width: 800px;
                margin-right: auto;
                margin-left: auto;
            \}
            .wrapper h2 \{
                color: #424242;
                padding-bottom: 10px;
                border-bottom: grey solid 1px;
            \}

            ul.item-list \{
                list-style: none;    
                padding-left: 15px;
            \}

            .item-list > li \{
            \}

            .item-list .item-link \{
                font-size: 18px;
            \}
            </style>
        </head>
        <body>
            <div class="page-content">
                <div class="wrapper">
                    <h2> Documents </h2>
                    <ul class="item-list">
                    @items
                    </ul>
                </div>
            </div>
        </body
        </html>
    }

    files_to_process = Dir.glob(files_to_scan).map {|f| file_info f}
    if (not to_docx) and files_to_process then
        index_items = files_to_process.map do |finfo|
            (_,title,_,mtime) = finfo
            index_item_tpl.gsub("@item-href", "#{title}.html").gsub("@item-title", title) 
        end
        index_page = index_page_tpl.gsub("@items", index_items.join("\n"))
        File.write("#{dest_dir}/index.html", index_page)
    end

    files_to_process.each  do |finfo|
        generate_md.call finfo 
    end
end
