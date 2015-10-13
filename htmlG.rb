#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
require 'erb'
require 'uri'
require 'yaml'
require 'ostruct'

version = "htmlG 0.1"
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
  
  opts.on_tail("--version", "Show version info") do
        puts version
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
    file = finfo.fullname
    base_name = finfo.basename
    file_ext = finfo.extname
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
    mtime = File.mtime f
    OpenStruct.new(:fullname=> f, :basename=>base_name, :extname=>file_ext, :mtime=>mtime)
end

puts "assciidoctor options: #{adoc_opts}" if verbose
puts "pandoc options: #{pandoc_opts}" if verbose

if f then
    generate_md.call(file_info(f))
else
       
    files_to_scan = "#{base_dir}/*.{md,markdown,adoc,asciidoc}"
    puts "Processing: #{files_to_scan}..." if verbose

    index_item_tpl = %(
        <li>
            <span class="item-meta" title="@item-meta-tip">@item-meta</span>
            <a class="item-link" href="@item-href">@item-title</a>
        </li>)
    index_page_tpl = %(
        <!DOCTYPE html>
        <html>
        <head>
            <title>Index</title>
            <style>
            body {
                font-family: Helvetica, Arial, sans-serif;
                font-weight: 300;
            }
            .page-content {
                padding: 30px 0;
                font-size: 16px;
                line-height:1.5;
                color: #111;
            }
            .wrapper {
                max-width: 800px;
                margin-right: auto;
                margin-left: auto;
            }
            .wrapper h2 {
                color: #424242;
                padding-bottom: 10px;
                border-bottom: grey solid 1px;
                font-size: 22px;
                line-height: 56px;
                letter-spacing: -1px;
            }

            ul.item-list {
                list-style: none;    
                padding-left: 15px;
                min-height: 400px;
            }

            .item-list > li {
            }

            .item-list .item-link {
                font-size: 18px;
                margin-left: 15px;
            }
            .item-list .item-meta {
                font-size: 14px;
                color: #828282;
                display: inline-block;
                width: 100px;
            }
            .wrapper .page-meta {
                border-top: grey solid 1px;
                text-align: right;
            }
            </style>
        </head>
        <body>
            <div class="page-content">
                <div class="wrapper">
                    <h2> Documents </h2>
                    <ul class="item-list">
                    @items
                    </ul>
                    <div class="page-meta">Powered by htmlG</div>
                </div>
            </div>
        </body
        </html>
    )
    
    build_log_file = "#{dest_dir}/_build.yaml"
    build_log = if File.file? build_log_file then YAML.load(File.read build_log_file) else {} end
    this_processing_time = Time.now
    files_with_ptime = 
        Dir.glob(files_to_scan).map do |f|
            finfo = file_info f
            finfo.ptime = (build_log[finfo.basename] or nil)
            finfo
        end
        .sort do |a,b| 
            b.mtime <=> a.mtime
        end

    files_to_process = files_with_ptime.select {|finfo| finfo.ptime.nil? or finfo.ptime < finfo.mtime}
    same_files_set = files_with_ptime.collect {|finfo| finfo.basename}.sort == build_log.keys.sort
    
    if ((not files_to_process.empty?) or (not same_files_set)) then
        to_copy = ["#{base_dir}/_css","#{base_dir}/_images","#{base_dir}/_scripts"].select {|d| File.directory? d}
        puts "Copying resources #{to_copy}..." if verbose and to_copy
        to_copy.each do |r|
            FileUtils.cp_r r,dest_dir
        end

        new_build_log = 
            Hash[files_with_ptime.collect {|finfo| [finfo.basename, finfo.ptime]}]
            .merge!(Hash[files_to_process.collect {|finfo| [finfo.basename, this_processing_time]}])
        
        File.write build_log_file,YAML.dump(new_build_log)
        puts "Build log generated." if verbose

        files_to_process.each  do |finfo|
            generate_md.call finfo 
            puts "Processed file #{finfo.fullname}." if verbose
        end

        if (not to_docx) then
            index_items = files_with_ptime.map do |finfo|
                title = finfo.basename
                mtime = finfo.mtime
                index_item_tpl
                    .gsub("@item-href", URI::encode("#{title}.html"))
                    .gsub("@item-title", ERB::Util.h(title))
                    .gsub("@item-meta-tip", ERB::Util.h(mtime.strftime("%T")))
                    .gsub("@item-meta", ERB::Util.h(mtime.strftime("%b %-d, %Y")))
            end
            index_page = index_page_tpl.gsub("@items", index_items.join("\n"))
            File.write("#{dest_dir}/index.html", index_page)
            puts "Index file generated." if verbose
        end
    end
end
