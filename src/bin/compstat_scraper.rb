#!/usr/bin/env ruby
# encoding: utf-8

# Usage: `./bin/compstat_scraper.rb`
# Takes no arguments.

require_relative '../lib/compstat_parser.rb'
require 'optparse'
module Compstat
  def self.scrape!
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
end


if __FILE__ == $0
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: status_checker.rb [options]"

    opts.on("-d", "--daemonize", "Run always, only scrape on schedule") do |v|
      options[:daemonize] = v
    end
  end.parse!

  if options[:daemonize]
    START_HOUR = 12
    START_MINUTE = 30
    DAYS = [1, 4, 5]
    WINDOW = 10
    puts "waiting for #{START_HOUR}:#{START_MINUTE} "
    while 1
      d = DateTime.now 
      puts "🎸🤠 it's #{d.hour}:#{d.minute} somewhere 🎸🤠"
      if d.hour == START_HOUR && d.minute > START_MINUTE && d.minute < (START_MINUTE + WINDOW) && DAYS.include?(d.wday)
        puts "oh sweet time to do stuff, it's #{d.hour}:#{d.minute}"
        Compstat.scrape!
      end
      sleep 60 * WINDOW
    end
  else
    Compstat.scrape!
  end
end
