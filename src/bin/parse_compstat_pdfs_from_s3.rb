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
  # config can also be specified as env vars. 
  config_file_path = File.join(File.dirname(File.expand_path(__FILE__)), '..', 'config.yml')
  config = File.exists?(config_file_path) ? (YAML::load_file(config_file_path) || {}) : {}

  compstat_parser = CompstatParser.new(config)
  creds = Aws::Credentials.new(ENV["AWS_ACCESS_KEY_ID"] || (config && config['aws'] ? config['aws']['access_key_id'] : nil), 
                       ENV["AWS_SECRET_ACCESS_KEY"] || (config && config['aws'] ? config['aws']['secret_access_key'] : nil))
  raise ArgumentError, "AWS -> S3 -> bucket details must be specified in config.yml (or env vars)" unless (config['aws'] && config['aws']['s3'] && config['aws']['s3']['bucket']) || ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_S3_BUCKET_PATH", "AWS_S3_BUCKET", "AWS_S3_REGION"].all?{|key| ENV.has_key?(key) }
  s3 = Aws::S3::Client.new(region: ENV["AWS_S3_REGION"] || (config && config['aws'] && config['aws']['s3'] ? config['aws']['s3']['region'] : 'us-east-1'), credentials: creds)
  pdf_keys = []

  # get a list of PDFs to parse
  s3.list_objects( bucket: ENV["AWS_S3_BUCKET"] || config['aws']['s3']['bucket'], 
                   prefix: ENV["AWS_S3_BUCKET_PATH"] || config['aws']['s3']['bucket_path']).each do |response|
    pdf_keys += response.contents.map(&:key)
  end
  # filter them based on the prefix (specified on the command line), if present
  pdf_keys.select!{|key| key.include?(ARGV[0])} if ARGV[0]

  pdf_keys.each do |key|

    # get each PDF and read it    
    resp = s3.get_object(bucket: ENV['AWS_S3_BUCKET'] || config['aws']['s3']['bucket'], key: key )
    pdf_contents = resp.body.read

    # extract the data from it
    compstat_parser.process(pdf_contents, key, nil)
  end
end
