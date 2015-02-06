#!/usr/bin/env ruby
# encoding: utf-8

# Usage: `./bin/compstat_scraper.rb`
# Takes no arguments.

require_relative '../lib/compstat_parser.rb'

if __FILE__ == $0
  # load config and initialize parser
  config = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), '..', 'config.yml')) || {}
  compstat_parser = CompstatParser.new(config)

  # scrape each precinct's report from the NYPD site
  scraper = Upton::Scraper.new("http://www.nyc.gov/html/nypd/html/crime_prevention/crime_statistics.shtml", '.bodytext table td a')
  scraper.sleep_time_between_requests = 3
  # download and extract data from each one
  scraper.scrape{ |pdf, url| compstat_parser.process(pdf, url) } 

  # and download the citywide report
  citywide_url = 'http://www.nyc.gov/html/nypd/downloads/pdf/crime_statistics/cscity.pdf'
  citywide_pdf = Net::HTTP.get(URI(citywide_url))
  # and extract data from it
  compstat_parser.process(citywide_pdf, citywide_url)
end
