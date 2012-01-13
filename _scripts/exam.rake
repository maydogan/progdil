#!/usr/bin/ruby
# encoding: utf-8

require 'yaml'
require 'erb'

## for _templates/_exam.md.erb global variable
@fullname = "Recai Oktaş"
@account = "roktas"
@email = "roktas@bil.omu.edu.tr"

TEMPLATE = ERB.new(File.read('_templates/exam.md.erb'))

task :exam => [:md, :pdf]

task :md do
  puts "yaml' dan markdown üretiliyor... "
  Dir["_exams/*.yml"].each do |yaml|
    _exam = YAML.load(File.open(yaml))
    _exam_outfile_md = "_exams/#{File.basename(yaml).split('.')[0]}.md"

    # create yaml to markdown
    File.open(_exam_outfile_md, "w") do |f|
      f.puts "# #{_exam['title']}"
      _exam['q'].each do |question|
        f.puts "- #{File.read("_includes/q/#{question[0]}")}\n"
        f.puts "![foo](_includes/q/media/#{question[1]})\n\n"
      end
      f.puts "#{TEMPLATE.result}"
      f.puts "## #{_exam['footer']}"
    end
  end
end

task :pdf do
  puts "markdown' dan pdf üretiliyor..."
  Dir["_exams/*.md"].each do |markdown|
    _exam_outfile = "_exams/#{File.basename(markdown).split('.')[0]}"
    sh "markdown2pdf #{_exam_outfile}.md > #{_exam_outfile}.pdf"
  end
end
