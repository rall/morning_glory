require File.dirname(__FILE__) + "/../morning_glory"
require 'heroku'
require 'heroku/command'

namespace :morning_glory do
  namespace :cloudfront do

    @@prev_cdn_revision = nil
    @@scm_commit_required = false
    
    def get_heroku_config!
      user, pass = File.read(File.expand_path("~/.heroku/credentials")).split("\n")
      heroku = Heroku::Client.new(user, pass)
      cmd = Heroku::Command::BaseWithApp.new([])
      remotes = cmd.git_remotes(File.dirname(__FILE__) + "/../..")
      app = remotes.detect {|key, value| value == (ENV['APP'] || cmd.app)}.last
      heroku_config = heroku.config_vars(app)
    end
    
    def morning_glory_config
      @morning_glory_config ||= begin
        local_config = YAML.load_file("#{RAILS_ROOT}/config/morning_glory.yml")
        heroku_config = get_heroku_config!
        local_config.merge("bucket" => heroku_config['S3_BUCKET'])
      end
    end
    
    def s3_config
      @s3_config ||= begin
        local_config = YAML.load_file("#{RAILS_ROOT}/config/s3.yml")
        heroku_config = get_heroku_config!
        local_config.merge("access_key_id" => heroku_config['S3_KEY'], "secret_access_key" => heroku_config['S3_SECRET'])
      end
    end
    
    def check_config
      if !defined? morning_glory_config[Rails.env] || morning_glory_config[Rails.env]['enabled'] != true
          raise "Deployment appears to be disabled for this environment (#{Rails.env}) within config/morning_glory.yml. Specify an alternative environment with RAILS_ENV={environment name}."
      end
      if !defined? s3_config[Rails.env]
        raise "You seem to be lacking your Amazon S3 configuration file, config/s3.yml"
      end
    end
    
    def get_revision
      rev = nil

      # GIT
      begin
        git_rev = `git show --pretty=format:"%H|%ci" --quiet`.split('|')[0]
        if !git_rev.nil?
          rev = git_rev.to_s
          puts '* Using Git revision'
        end
      rescue
        # Ignore
      end
      # SVN
      begin
        svn_rev = `svnversion .`.chomp.gsub(':','_')
        puts svn_rev
        if svn_rev != 'exported' && svn_rev != '' && svn_rev != nil
          rev = Digest::MD5.hexdigest( svn_rev ).to_s
          puts '* Using SVN revision'
        end
      rescue
        # Ignore
      end
      
      if rev.nil?
        rev = Time.new.strftime("%Y%m%d%H%M%S") 
        puts '* Using timestamp revision'
        @@scm_commit_required = true
      end
      
      return rev
    end

    def update_revision
      prev = morning_glory_config['revision'].to_s

      rev = get_revision
      
      morning_glory_config['revision'] = rev
      ENV['RAILS_ASSET_ID'] = CLOUDFRONT_REVISION_PREFIX + rev
    
      # Store the previous revision so we can delete the bucket from S3 later after deploy
      @@prev_cdn_revision = CLOUDFRONT_REVISION_PREFIX + prev
    
      File.open("#{RAILS_ROOT}/config/morning_glory.yml", 'w') { |f| YAML.dump(morning_glory_config, f) }
    
      puts "* CDN revision updated for '#{Rails.env}' environment to #{ENV['RAILS_ASSET_ID']}" 
    end

    def compile_sass_if_available
      if defined? Sass
        puts "* Compiling Sass stylesheets"
        Sass::Plugin.update_stylesheets
      end
    end

    desc "Bump the revision, compile any Sass stylesheets, and deploy assets to S3 and Cloudfront"
    task :deploy => [:environment] do |t, args|
      require 'aws/s3'
      require 'ftools'
      
      puts 'MorningGlory: Starting deployment to the Cloudfront CDN...'
      
      check_config
      
      update_revision

      compile_sass_if_available

      # Constants
      SYNC_DIRECTORY  = File.join(Rails.root, 'public')
      TEMP_DIRECTORY  = File.join(Rails.root, 'tmp', 'morning_glory', 'cloudfront', Rails.env, ENV['RAILS_ASSET_ID']);
      # Configuration constants
      BUCKET          = morning_glory_config['bucket'] || Rails.env
      DIRECTORIES     = morning_glory_config[Rails.env]['asset_directories'] || %w(images javascripts stylesheets)
      CONTENT_TYPES   = morning_glory_config[Rails.env]['content_types'] || {
                          :jpg => 'image/jpeg',
                          :png => 'image/png',
                          :gif => 'image/gif',
                          :css => 'text/css',
                          :js  => 'text/javascript'
                        }
      S3_LOGGING_ENABLED = morning_glory_config[Rails.env]['s3_logging_enabled'] || false
      DELETE_PREV_REVISION = morning_glory_config[Rails.env]['delete_prev_rev'] || false
      REGEX_ROOT_RELATIVE_CSS_URL = /url\((\'|\")?(\/+.*(#{CONTENT_TYPES.keys.map { |k| '\.' + k.to_s }.join('|')}))\1?\)/
    
      # Copy all the assets into the temp directory for processing
      File.makedirs TEMP_DIRECTORY if !FileTest::directory?(TEMP_DIRECTORY)
      puts "* Copying files to working directory for cache-busting-renaming"
      DIRECTORIES.each do |directory|
        Dir[File.join(SYNC_DIRECTORY, directory, '**', "*.{#{CONTENT_TYPES.keys.join(',')}}")].each do |file|
          file_path = file.gsub(/.*public\//, "")
          temp_file_path = File.join(TEMP_DIRECTORY, file_path)

          File.makedirs(File.dirname(temp_file_path)) if !FileTest::directory?(File.dirname(temp_file_path))
        
          puts " ** Copied to #{temp_file_path}"
          FileUtils.copy file, temp_file_path
        end
      end

      puts "* Replacing image references within CSS files"
      DIRECTORIES.each do |directory|
        Dir[File.join(TEMP_DIRECTORY, directory, '**', "*.{css}")].each do |file|
          puts " ** Renaming image references within #{file}"
          buffer = File.new(file,'r').read.gsub(REGEX_ROOT_RELATIVE_CSS_URL) { |m| m.insert m.index('(') + ($1 ? 2 : 1), '/'+ENV['RAILS_ASSET_ID'] }
          File.open(file,'w') {|fw| fw.write(buffer)}
        end
      end

      # TODO: Update references within JS files
    
      AWS::S3::Base.establish_connection!(
        :access_key_id     => s3_config['access_key_id'],
        :secret_access_key => s3_config['secret_access_key']
      )

      begin
        puts "* Attempting to create S3 Bucket '#{BUCKET}'"
        AWS::S3::Bucket.create(BUCKET)
      
        AWS::S3::Bucket.enable_logging_for(BUCKET) if S3_LOGGING_ENABLED

        puts "* Uploading files to S3 Bucket '#{BUCKET}'"
        DIRECTORIES.each do |directory|
          Dir[File.join(TEMP_DIRECTORY, directory, '**', "*.{#{CONTENT_TYPES.keys.join(',')}}")].each do |file|
            file_path = file.gsub(/.*#{TEMP_DIRECTORY}\//, "")
            file_path = File.join(ENV['RAILS_ASSET_ID'], file_path)
            file_ext = file.split(/\./)[-1].to_sym
          
            puts " ** Uploading #{BUCKET}/#{file_path}"
            AWS::S3::S3Object.store(file_path, open(file), BUCKET,
              :access => :public_read,
              :content_type => CONTENT_TYPES[file_ext])
          end
        end

        # If the configured to delete the prev revision, and the prev revision value was in the YAML (not the blank concat of CLOUDFRONT_REVISION_PREFIX + revision number)
        if DELETE_PREV_REVISION && @@prev_cdn_revision != CLOUDFRONT_REVISION_PREFIX
          # TODO: Figure out how to delete from the S3 bucket properly
          puts "* Deleting previous CDN revision #{BUCKET}/#{@@prev_cdn_revision}"
          AWS::S3::Bucket.find(BUCKET).objects(:prefix => @@prev_cdn_revision).each do |object|
            puts " ** Deleting #{BUCKET}/#{object.key}"
            object.delete
          end
        end
      rescue
        raise
      ensure
        puts "* Deleting temp cache files in #{TEMP_DIRECTORY}"
        FileUtils.rm_r TEMP_DIRECTORY
      end
      
      puts "MorningGlory: DONE! Your assets have been deployed to the Cloudfront CDN."
      
      if @@scm_commit_required == true
        puts '='*80
        puts "NB: You will need to commit the /config/morning_glory.yml file and update it on your servers."
        puts '='*80
      end
    end
  end
end