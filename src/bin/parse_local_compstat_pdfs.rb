#!/usr/bin/env ruby
# encoding: utf-8

# Usage: 
# e.g. ./bin/parse_local_compstat_pdfs.rb "input/*/*.pdf"


require_relative '../lib/compstat_parser.rb'

if __FILE__ == $0

  # load config and initialize parser. config can also be specified as env vars. 
  config_file_path = File.join(File.dirname(File.expand_path(__FILE__)), '..', 'config.yml')
  config = File.exists?(config_file_path) ? (YAML::load_file(config_file_path) || {}) : {}
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
