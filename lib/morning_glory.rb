# Prefix files with a revision to bust the cloudfront non-expiring cache. For instance, /REV_1234/myfile.png
CLOUDFRONT_REVISION_PREFIX = 'REV_'

module MorningGlory
  # Nothing
end

begin
  bucket_from_heroku_config = ENV.has_key?('S3_BUCKET') ? { :bucket => ENV['S3_BUCKET'] } : {}
  MORNING_GLORY_CONFIG = YAML.load_file("#{RAILS_ROOT}/config/morning_glory.yml").merge(bucket_from_heroku_config) if !defined? MORNING_GLORY_CONFIG
rescue
  raise "Error loading MorningGlory configuration files. Please check config/morning_glory.yml is configured correctly."
end

S3_CONFIG = begin
  if ENV.has_key?('S3_KEY') and ENV.has_key?('S3_SECRET')
    { :access_key_id => ENV['S3_KEY'], :secret_access_key => ENV['S3_SECRET'] }
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
