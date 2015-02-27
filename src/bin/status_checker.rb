#!/usr/bin/env ruby
# encoding: utf-8

# Usage:
# ./bin/status_checker.rb
# Takes no arguments 
# checks for this week's (and last week's) compstat reports and sends an email if they're not found

require 'active_record'
require 'activerecord-jdbcmysql-adapter'
require 'yaml'
require 'aws-sdk-v1'
require 'active_support/time'

EXPECTED_REPORTS = 85



if __FILE__ == $0

  # initialize connections to the database and to S3
  config = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), '..', 'config.yml')) || {}
  raise ArgumentError, "MySQL connection info must be specified in config.yml" if !config || !config['mysql']  
  ActiveRecord::Base.establish_connection(:adapter => 'jdbcmysql', :host => config['mysql']['host'], :username => config['mysql']['username'], :password => config['mysql']['password'], :port => config['mysql']['port'], :database => config['mysql']['database']) 
  AWS.config(access_key_id: config['aws']['access_key_id'], secret_access_key: config['aws']['secret_access_key'])
  snes = AWS::SNS::Topic.new(config['aws']['sns']['topic_arn'])
  raise ArgumentError, "AWS SNS topic ARN must be speciifed in config.yml" unless  config['aws']['sns']['topic_arn']

  # check if records for the week of a given date exist in the database
  def is_missing_compstats(date_obj)
    query_end_date = date_obj.strftime('%Y-%m-%d')
    query_start_date = (date_obj-7.days).strftime('%Y-%m-%d')
    count = ActiveRecord::Base.connection.execute("SELECT count(*) as cnt FROM crimes_by_precinct WHERE end_date >= '#{query_start_date}' AND start_date <= '#{query_end_date}'")
    EXPECTED_REPORTS - count[0]['cnt'].to_i
  end

  weeks_we_have = ActiveRecord::Base.connection.execute("select distinct start_date, end_date from crimes_citywide order by start_date desc;")

  last_few_reports = weeks_we_have.map{|row| row['start_date'].to_s[0...10] + " - " + row['end_date'].to_s[0...10]}[0...4]

  # check for this week and last week
  this_week = Time.now
  last_week = Time.now - 7.days

  messages = []
  okay_messages = []
  subject_emoji = nil
  subject_items = []

  # compose a message if this week is missing its reports  
  if (missing_cnt = is_missing_compstats(this_week))
    if missing_cnt < EXPECTED_REPORTS
      messages << "Yikes! #{missing_cnt} reports are missing from the compstat scraper for this week (ending #{this_week}). Or maybe something went wrong)."
      subject_emoji ||= "❓👮📉 CompStat:"
      subject_items << "missing reports for this week (#{this_week.to_s[5..9].gsub('-', '/').gsub(/^0*/, '')})"  # only used for email.
    else
      messages << "Uh oh! There are no compstat reports for this week (ending #{this_week}). Or maybe something went wrong..."
      subject_emoji ||= "😖👮📉 CompStat:"
      subject_items << "no reports for this week (#{this_week.to_s[5..9].gsub('-', '/').gsub(/^0*/, '')})"  # only used for email.
    end
  else
    okay_messages << "but THIS week's compstat reports okay."  
  end

  # compose a message if last week is missing its reports  
  if ((missing_cnt = is_missing_compstats(last_week)) > 0 && last_week > Date.new(2015,1,6))
    if missing_cnt < EXPECTED_REPORTS
      messages << "Pick up the phone! #{missing_cnt} reports are missing from the compstat scraper for last week (ending #{last_week}). Or maybe something went wrong."
      subject_emoji ||= "📞👮📉 CompStat:"
      subject_items << "missing reports for LAST week (#{last_week.to_s[5..9].gsub('-', '/').gsub(/^0*/, '')})"  # only used for email.
    else
      messages << "Jinkies! There are no compstat reports for LAST week (ending #{last_week}). Or maybe something went wrong..."
      subject_emoji ||= "💢👮📉 CompStat:"
      subject_items << "no reports for LAST week (#{last_week.to_s[5..9].gsub('-', '/').gsub(/^0*/, '')})"  # only used for email.
    end
  else
    okay_messages << "but LAST week's compstat reports okay."  
  end

  # send the email
  message = (messages + okay_messages).join("\n\n")
  message += "\n Last few reports: \n" + last_few_reports.join("\n")
  subject = "#{subject_emoji}: #{subject_items.join(" and ")}"[0...98]
  snes.publish(message , {subject: subject} ) unless messages.empty?
end
