#!/usr/bin/env ruby
# encoding: utf-8

# Usage: 
# e.g. ./bin/parse_local_compstat_pdfs.rb "input/*/*.pdf"


require_relative '../lib/compstat_parser.rb'

if __FILE__ == $0

  # initialize the parser
  config = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), '..', 'config.yml')) || {}
  compstat_parser = CompstatParser.new(config)
  
  # for each set of files
  ARGV.each do |glob| 
    Dir[glob + (glob.include?("*") || glob.match(/\.pdf$/) ? '' : "/**/*.pdf")].each do |filepath|
      next unless File.exists?(filepath)

      # open the DPF
      pdf_contents = open(filepath, 'rb'){|f| f.read }

      # and extract the data from it.
      compstat_parser.process(pdf_contents, filepath, nil)
    end
  end
end
