#!/usr/bin/env ruby
# encoding: utf-8

# Usage: `./bin/compstat_scraper.rb`
# Takes no arguments.

require_relative '../lib/compstat_parser.rb'

if __FILE__ == $0
  # load config and initialize parser. config can also be specified as env vars. 
  config_file_path = File.join(File.dirname(File.expand_path(__FILE__)), '..', 'config.yml')
  config = File.exists?(config_file_path) ? (YAML::load_file(config_file_path) || {}) : {}
  
  compstat_parser = CompstatParser.new(config)

  # scrape each precinct's report from the NYPD site
  scraper = Upton::Scraper.new("http://www.nyc.gov/html/nypd/html/crime_prevention/crime_statistics.shtml", ".bodytext table td a[href$='.pdf']")
  scraper.sleep_time_between_requests = 3
  scraper.debug = false
  # download and extract data from each one
  scraper.scrape{ |pdf, url| puts url; compstat_parser.process(pdf, url) } 

  # and download the citywide report
  citywide_url = 'http://www.nyc.gov/html/nypd/downloads/pdf/crime_statistics/cs-en-us-city.pdf'
  citywide_pdf = Net::HTTP.get(URI(citywide_url))
  # and extract data from it
  compstat_parser.process(citywide_pdf, citywide_url)
end
