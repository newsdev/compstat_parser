#!/usr/bin/env ruby
# encoding: utf-8


# Usage: 
# e.g. ./bin/parse_compstat_reports_from_s3.rb "compstat/"
# the second argument is a "prefix" -- if you want to parse a subset of the files (e.g. one month)


require 'aws-sdk' # uses AWS SDK v2.0
require 'yaml'
require_relative '../lib/compstat_parser.rb'

if __FILE__ == $0

  # initialize connection to S3 and initialize parser
  config = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), '..', 'config.yml')) || {}
  compstat_parser = CompstatParser.new(config)
  creds = Aws::Credentials.new(config['aws']['access_key_id'], 
                       config['aws']['secret_access_key'])
  raise ArgumentError, "AWS -> S3 -> bucket details must be specified in config.yml" unless config['aws'] && config['aws']['s3'] && config['aws']['s3']['bucket']
  s3 = Aws::S3::Client.new(region: config['aws']['s3']['region'] || 'us-east-1', credentials: creds)
  pdf_keys = []

  # get a list of PDFs to parse
  s3.list_objects(bucket: config['aws']['s3']['bucket'], prefix: config['aws']['s3']['bucket_path']).each do |response|
    pdf_keys += response.contents.map(&:key)
  end

  # filter them based on the prefix (specified on the command line), if present
  pdf_keys.select!{|key| key.include?(ARGV[0])} if ARGV[0]

  pdf_keys.each do |key|

    # get each PDF and read it    
    resp = s3.get_object(bucket: config['aws']['s3']['bucket'], key: key )
    pdf_contents = resp.body.read

    # extract the data from it
    compstat_parser.process(pdf_contents, key, nil)
  end
end
