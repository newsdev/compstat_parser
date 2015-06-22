#!/usr/bin/env jruby
# encoding: utf-8

# you can require this file if you'd like to use it in another script.
require 'upton'
require 'fileutils'
require 's3-publisher'
require 'aws-sdk-v1'
require 'active_record'
require 'activerecord-jdbcmysql-adapter'
require 'yaml'
require 'tabula'
require 'tmpdir'

# A list of headers, in computerese, in order of the rows in the CompStat PDFs (which have total in the middle, for some reason)
CRIME_HEADERS = ['murder',
                 'rape',
                 'robbery',
                 'felony_assault',
                 'burglary',
                 'grand_larceny',
                 'grand_larceny_auto',
                 'total',
                 'transit',
                 'housing',
                 'petit_larceny',
                 'misdemeanor_assault',
                 'misdemeanor_sex_crimes',
                 'shooting_victims',
                 'shooting_inc']

# A list of headers, as they appear in the PDFs.
RAW_CRIME_HEADERS =['Murder',
                    'Rape',
                    'Robbery',
                    'Fel. Assault',
                    'Burglary',
                    'Gr. Larceny',
                    'G.L.A.',
                    'TOTAL',
                    'Transit',
                    'Housing',
                    'Petit Larceny',
                    'Misd. Assault',
                    'Misd. Sex Crimes',
                    'Shooting Vic.',
                    'Shooting Inc.']
CRIME_HEADER_TRANSLATION = Hash[*RAW_CRIME_HEADERS.zip(CRIME_HEADERS).flatten]


DEFAULT_NAME = "compstat"
class CompstatParser
  def initialize(config)
    # setup the places we're going to put our data (MySQL and a CSV for data, S3 for pdfs).
    @config = config
    @mysql_table_names = ["crimes_citywide", "crimes_by_precinct"]
    @csv_output = ENV.has_key?("CSV") ? ENV["CSV"] : (@config.has_key?("csv") ? @config["csv"] : "crime_stats.csv")
    open(@csv_output , 'wb'){|f| f << "#{CompStatReport.unique_identifiers.map(&:first).map(&:to_s).join(',')}, " + CRIME_HEADERS.join(", ") +', ' +CRIME_HEADERS.map{|h| "#{h}_last_year"}.join(", ") + "\n"} unless !@csv_output || File.exists?(@csv_output)
    AWS.config(access_key_id: ENV["AWS_ACCESS_KEY_ID"] || (@config && @config['aws'] ? @config['aws']['access_key_id']: nil) , secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"] || (@config && @config['aws'] ? @config['aws']['secret_access_key'] : nil)) if ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"].all?{|key| ENV.has_key?(key) } || @config['aws']
    ActiveRecord::Base.establish_connection(
      :adapter => 'jdbcmysql', 
      :host => ENV["MYSQL_HOST"] || (config && config['mysql'] ? config['mysql']['host'] : nil), 
      :username => ENV["MYSQL_USERNAME"] || (config && config['mysql'] ? config['mysql']['username'] : nil), 
      :password => ENV["MYSQL_PASSWORD"] || (config && config['mysql'] ? config['mysql']['password'] : nil), 
      :port => ENV["MYSQL_PORT"] || (config && config['mysql'] ? config['mysql']['port'] : nil), 
      :database => ENV["MYSQL_DATABASE"] || (config && config['mysql'] ? config['mysql']['database'] : nil)
    ) if (@config && @config['mysql']) || ["MYSQL_HOST","MYSQL_USERNAME","MYSQL_PASSWORD","MYSQL_PORT","MYSQL_DATABASE"].any?{|key| ENV.has_key?(key)}
    @mysql_table_names.each do |mysql_table_name|
      ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS #{mysql_table_name}(#{CompStatReport.unique_identifiers.map{|col, type| "#{col} #{type}"}.join(',') }, "+
        CRIME_HEADERS.join(" integer,")+" integer, " +
        CRIME_HEADERS.join("_last_year integer,")+"_last_year integer" +
        ")") if @config["mysql"] || ["MYSQL_HOST","MYSQL_USERNAME","MYSQL_PASSWORD","MYSQL_PORT","MYSQL_DATABASE"].any?{|key| ENV.has_key?(key)}
    end
    @s3 = AWS::S3.new
  end

  # transform a PDF into the data we want to extract
  def parse_pdf(pdf, pdf_basename, pct=nil)
    tmp_dir = File.join(Dir::tmpdir, DEFAULT_NAME)
    Dir.mkdir(tmp_dir) unless Dir.exists?(tmp_dir)

    open( pdf_path = File.join(tmp_dir, pdf_basename) , 'wb'){|f| f << pdf} # we need to write the file to disk for Tabula to use it.  
    
    ##
    # You can get dimensions like this by loading up Tabula's GUI
    # and selecting "download as tabula-extractor script" then copy/pasting the dimensions
    # from the shell command there. They're not exact and may take some fiddling
    ##
    this_year_crimes_dimensions = [253.543,136.607,485.229,186.879]
    last_year_dimensions = [257.914,177.043,484.136,215.293]
    this_year_and_last_year_crimes_dimensions = [255.729,134.421,484.136,220.757]

    headers_dimensions =   [255.729,39.343,483.043,136.607]
    dates_dimensions = [183.6,138.793,205.457,475.393]

    ### pre-2012, the format changed changed: 
    # these aren't used here, but you can adapt this to do so, if you want.
    dates_dimensions = [182.507,292.886,204.364,472.114]

    # early June 2015 dates_dimensions (courtesy of Lela Prashad)
    dates_dimensions = [153.7,183.4,184.5,455.8]

    # June 22 and after dates_dimensions
    dates_dimensions = [177.48, 206.4725, 191.25, 382.1175]

    this_year_and_last_year_crimes_dimensions = [254.636,124.586,361.736,183.6]

    # open the PDF
    begin
      page = (extractor = Tabula::Extraction::ObjectExtractor.new(pdf_path, [1])).extract.first
    rescue java.io.IOException => e
      puts "Failed to open PDF #{e.message}"
      return nil
    end

    # extract the data we want, using those dimensions
    start_date, end_date = *page.get_area(dates_dimensions).get_table.rows.to_a[0][0].text.scan(/(\d\d?)\/(\d\d?)\/(\d\d\d\d)/).map{|date_parts| [date_parts.pop, *date_parts].join("-")}
    headers, crime_counts = [headers_dimensions, this_year_and_last_year_crimes_dimensions].map do |dims|
      page.get_area( dims ).get_table.cols.map{|col| col.map(&:text) }
    end

    # transform the crimes into a Hash
    crime_counts = Hash[*['this_year', 'last_year'].zip(crime_counts).flatten(1)]
    extractor.close!

    #create and return an object with our data
    CompStatReport.new(pct, start_date, end_date, crime_counts, pdf_path, headers[0])
  end

  def process(pdf_data, pdf_path, trash=nil)
    # parse the given PDF
    report = parse_pdf( pdf_data, (pdf_basename = pdf_path.split("/")[-1]), (pct = pdf_basename.split('.pdf')[0].gsub('cs', '').gsub('pct', '') ) )
    return if report.nil?

    # if this report is already in the database, don't put it in the DB (and assume it exists in S3, perhaps under another date)
    table_name = report.precinct == 'city' ? @mysql_table_names[0] : @mysql_table_names[1]
    return if 
              ((@config['mysql'] || ["MYSQL_HOST","MYSQL_USERNAME","MYSQL_PASSWORD","MYSQL_PORT","MYSQL_DATABASE"].any?{|key| ENV.has_key?(key)})) && 
              ActiveRecord::Base.connection.active? && 
              !ActiveRecord::Base.connection.execute("SELECT * FROM #{table_name} WHERE #{CompStatReport.unique_identifiers.map(&:first).map{|key| "#{key} = #{report.enquote_if_necessary(key)}"}.join(" AND ")}").empty?


    # add our data to MySQL, if config.yml (or env vars) says to.
    begin
      ActiveRecord::Base.connection.execute("INSERT INTO #{table_name}(#{CompStatReport.unique_identifiers.map(&:first).map(&:to_s).join(',')}, #{CRIME_HEADERS.join(',')+', ' +CRIME_HEADERS.map{|h| "#{h}_last_year"}.join(", ")}) VALUES (" + report.to_csv_row(true)+ ")") if (@config['mysql'] || ["MYSQL_HOST","MYSQL_USERNAME","MYSQL_PASSWORD","MYSQL_PORT","MYSQL_DATABASE"].any?{|key| ENV.has_key?(key)})
    rescue ActiveRecord::StatementInvalid => e
      puts "Error: #{pdf_path}"
      puts e.inspect
      puts "\n\n"
    end

    # N.B.: If there's no database, you'll get duplicate records in the CSV. 
    open(@csv_output, 'ab'){|f| f << report.to_csv_row + "\n"} if @csv_output

    puts report.unique_id

    # Save the file to disk and/or S3, if specified in config.yml
    if (@config['aws'] && @config['aws']['s3']) || ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_S3_BUCKET_PATH", "AWS_S3_BUCKET"].all?{|key| ENV.has_key?(key) }
      key = File.join(ENV["AWS_S3_BUCKET_PATH"] || @config['aws']['s3']['bucket_path'], report.start_date, pdf_basename)
      S3Publisher.publish(ENV["AWS_S3_BUCKET"] || @config['aws']['s3']['bucket'], {logger: 'faux /dev/null'}){ |p| p.push(key, data: pdf_data, gzip: false) } if @config['aws'] && !@s3.buckets[@config['aws']['s3']['bucket']].objects[key].exists?
    end
    if @config['local_pdfs_path'] || ENV["LOCAL_PDFS_PATH"]
      full_path = File.join(ENV["LOCAL_PDFS_PATH"] || @config['local_pdfs_path'], report.shared_id, pdf_basename)
      FileUtils.mkdir_p( File.dirname full_path )
      FileUtils.copy(report.path, full_path) unless File.exists?(full_path) # don't overwrite
    end
  end
end

# a class to represent the data contained in each report.
class CompStatReport

  def self.unique_identifiers
    [[:precinct, 'varchar(30)'], [:start_date, :datetime], [:end_date, :datetime]]
  end
  attr_accessor(:headers, *self.unique_identifiers.map(&:first))

  attr_accessor :start_date, :end_date, :precinct, :headers
  attr_reader :crimes, :path, :crimes_last_year
  def initialize pct, start_date, end_date, crimes_counts, path, headers
    @start_date = start_date
    @end_date = end_date    
    @precinct = pct
    @path = path

    @headers = headers.map{|header| CRIME_HEADER_TRANSLATION[header] }

    @crimes = Hash[*@headers.zip(crimes_counts['this_year'].map{|c| c.gsub(",", '').to_i }).flatten]
    @crimes_last_year  = Hash[*@headers.zip((crimes_counts['last_year'] || []).map{|c| c.gsub(",", '').to_i }).flatten]
  end

  # for insertion into a database.
  def enquote_if_necessary(method)
    if Hash[*self.class.unique_identifiers.flatten][method] == :integer
      send(method)
    else
      "'#{send(method)}'"
    end
  end  

  def to_a
    self.class.unique_identifiers.map(&:first).map{|field| self.send(field) } + CRIME_HEADERS.map{|h| @crimes[h].to_i} + CRIME_HEADERS.map{|h| @crimes_last_year[h].to_i}
  end

  def shared_id
    self.class.unique_identifiers[1..-1].map(&:first).map(&:to_s).join('_')
  end

  def unique_id
    self.class.unique_identifiers.map(&:first).map{|m|self.send(m)}.map(&:to_s).join('-')
  end

  def to_csv_row(enquote=false)
    to_a.map{|s| enquote ? "'#{s}'" : s.to_s}.join(",")
  end
end
