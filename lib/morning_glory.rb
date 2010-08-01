require 'heroku'
require 'heroku/command'

user, pass = File.read(File.expand_path("~/.heroku/credentials")).split("\n")
heroku = Heroku::Client.new(user, pass)
cmd = Heroku::Command::BaseWithApp.new([])
remotes = cmd.git_remotes(File.dirname(__FILE__) + "/../..")
app = remotes.detect {|key, value| value == (ENV['APP'] || cmd.app)}.last
heroku_config = heroku.config_vars(app)

# Prefix files with a revision to bust the cloudfront non-expiring cache. For instance, /REV_1234/myfile.png
CLOUDFRONT_REVISION_PREFIX = 'REV_'

module MorningGlory
  # Nothing
end

begin
  bucket_from_heroku_config = heroku_config.has_key?('S3_BUCKET') ? { :bucket => heroku_config['S3_BUCKET'] } : {}
  MORNING_GLORY_CONFIG = YAML.load_file("#{RAILS_ROOT}/config/morning_glory.yml").merge(bucket_from_heroku_config) if !defined? MORNING_GLORY_CONFIG
rescue
  raise "Error loading MorningGlory configuration files. Please check config/morning_glory.yml is configured correctly."
end

S3_CONFIG = begin
  if heroku_config.has_key?('S3_KEY') and heroku_config.has_key?('S3_SECRET')
    { :access_key_id => heroku_config['S3_KEY'], :secret_access_key => heroku_config['S3_SECRET'] }
  else
    YAML.load_file("#{RAILS_ROOT}/config/s3.yml")[Rails.env] if !defined? S3_CONFIG
  end
rescue
  raise "Error loading MorningGlory configuration files. Please set in your Heroku config or check config/s3.yml is configured correctly."
end

if defined? MORNING_GLORY_CONFIG
  if MORNING_GLORY_CONFIG[Rails.env]['enabled'] == true
    ENV['RAILS_ASSET_ID'] = CLOUDFRONT_REVISION_PREFIX + MORNING_GLORY_CONFIG[Rails.env]['revision'].to_s
  end
end
