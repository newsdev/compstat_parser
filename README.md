CompStat Parser
================

New York Police Department Complaint Statistics Scraper & Parser
----------------------------------------------------------------

This collection of tools scrapes the [N.Y.P.D.'s CompStat site](http://www.nyc.gov/html/nypd/html/crime_prevention/crime_statistics.shtml), downloads the crime stats that are published as PDFs each week for each precinct, then parses them into actual data -- CSVs.

This tool is designed to minimally output a CSV with current-week crime data, but more advanced options are available too.

After you install this tool (see below), you will be able to download the most recent PDFs from the NYPD's site and generate a CSV.

Installation
--------------

Run the commands following a `$` on the command line (like Terminal on a Mac). This assumes you have a Ruby version manager (like [RVM](https://rvm.io/) or [rbenv](https://github.com/sstephenson/rbenv)) and MySQL already installed on your machine.

````
$ git clone git@github.com:nytinteractive/compstat_parser.git
$ cd compstat_parser
$ rbenv install jruby-1.7.16 # or another recent JRuby version
$ rbenv local jruby-1.7.16
$ create database compstat # creates a database in MySQL called "compstat"
````

Optionally, fill in config.yml (based on the details in config.example.yml) if you want a database or PDFs saved to S3 (See the "Configuration Options" section below for more information.)

````
$ bundle install
$ compstat_scraper.rb #once the scraper is installed, execute it
````

Usage
-----

- `$ compstat_scraper.rb` (takes no arguments) Scrapes the most recent PDFs from the NYPD site.

Note that if you run the script multiple times without a database, rows will be duplicated in the CSV. You should dedupe it with UNIX's `uniq` tool, in Sublime Text or in Excel.


Advanced Options
================
This tool can also seamlessly run weekly via `cron` and interface with Amazon S3 for storage of PDFs and MySQL (or RDS) for stats. It can send you emails if crime stats aren't posted when you expect them to be, via Amazon's Simple Notifications Service (SNS). These options are set in a config file, `config.yml`. 

Depending on whether you're trying to parse locally-stored old PDFs or scrape and parse the N.Y.P.D.'s most current, this library supplies two additional executables (in src/bin/) : 

- `parse_local_compstat_pdfs.rb` (takes any number of arguments -- globs or folder paths that should be parsed) Scrapes data from locally-downloaded PDFs e.g. `ruby /bin/parse_local_compstat_pdfs.rb  "/Volumes/Stuff 19/old_compstat_pdfs/2014**/*" "/Volumes/Stuff 19/old_compstat_pdfs/2015**/*" "pdfs/2014-12-28/*" "pdfs/2015-1-4/*"`
- `parse_compstat_pdfs_from_s3.rb` (takes one optional argument, a "prefix" to PDFs in the S3 bucket)

A fouth executable, checks if data is arriving weekly as expected; if not, it sends you emails (with emoji!) to tell you to investigate.

- `status_checker.rb` (takes no arguments)

Configuration options
---------------------

See config.example.yml for a working example, or:
````
---
aws:
  access_key_id: whatever
  secret_access_key: whatever
  s3:
    bucket: mybucket
    bucket_path: moving_summonses
  sns:
    topic_arn: arn:aws:sns:region:1234567890:topic-name`
mysql:
  host: localhost
  username: root
  password:
  port: 
  database: 
local_pdfs_path: false # false means don't store PDFs locally, otherwise a path to a folder to store them
csv: 'crime_stats.csv' 
````

When any of these options are unspecified, they will be silently ignored. (However, if the settings are invalid, an error will be thrown.) For instance, if the `mysql` block isn't supplied, data will not be sent to MySQL; if AWS is unspecified, PDFs will not be uploaded to S3 and `status_checker.rb` will not send notifications by email. An exception is the `csv` key: if this is unset, data will be saved to `crime_stats.csv`; set it to "false" or 0 to prevent any CSV from being generated.

If MySQL is specified in the config file, two tables will be created (or appended to, if they already exist) in the specified database: `crimes_citywide` and `crimes_by_precinct`. The record layout for each table is identical: citywide summaries are located in `crimes_citywide` and precinct-by-precinct data is in `crimes_by_precinct`.

*All of these options can also be specified as ENV variables, flattening their paths, as follows:*
`AWS_ACCESS_KEY_ID=whatever AWS_SNS_TOPIC_ARN=arn:aws:sns:region:1234567890:topic-name`

Cron
----

You can use cron[https://en.wikipedia.org/wiki/Cron] to run this scraper automatically, on a regular basis. 

E.g. to set up a weekly-ish cron to run on Wednesdays, add this to your crontab. (Use `crontab -e` to edit it.)
`0 0 * * 4,5 /bin/bash/ -c 'export PATH="$HOME/.rbenv/bin:$PATH"; eval "$(rbenv init -)"; jruby -S ruby /bin/compstat_scraper.rb'`

DOCKER and boot2docker
------------------------

````
cd ./src
docker build compstat .
docker run -it compstat bundle exec jruby bin/compstat_scraper.rb
````

Export from MySQL to CSV:
-------------------------
To export from MySQL to CSV: 
````
mysql compstat -e "select * from crimes_by_precinct" | sed 's/	/","/g;s/^/"/;s/$/"/;s/\n//g' > crime_stats_from_mysql.csv
````
taking care to ensure that the first regex is a real tab. (If on Mac/BSD; on Unix, \t is fine.)


Want to contribute?
-------------------

I welcome your contributions. If you have suggestions or issues, please register them in the Github issues page. If you'd like to add a feature or fix a bug, please open a Github pull request. Or send me an email, I'm happy to guide you through the process.

And, if you're using these, please let me know. I'd love to hear from you!
