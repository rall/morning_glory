# Installation instructions
puts '=' * 80
puts <<EOF

MORNING GLORY CONFIG

See the github wiki for more detailed configuration information at:
http://wiki.github.com/adamburmister/morning_glory/

= Morning Glory =
You will need to manually create & configure your config/morning_glory.yml file.
Sample config/morning_glory.yml:

  --- 
  production: 
    delete_prev_rev: true
    s3_logging_enabled: true
    enabled: true
    asset_directories: 
    - images
    - javascripts
    - stylesheets
    revision: "20100316165112"
  staging: 
    enabled: true
  testing: 
    enabled: false
  development: 
    enabled: false


= Amazon AWS =
If you are using Heroku, set your S3 credentials using "heroku config" :

heroku config:add S3_KEY=[your S3 key]
heroku config:add S3_SECRET=[your S3 secret]
heroku config:add S3_BUCKET=[your S3 bucket]

You will also need to manually create & configure your config/s3.yml file (you can leave the values
for "bucket", "access_key_id" and  "secret_access_key" blank if they are in your Heroku environment).
This file contains your access credentials for accessing the Amazon S3 service.
Sample config/s3.yml:

  ---
  production:
    access_key_id: YOUR_ACCESS_KEY
    secret_access_key: YOUR_SECRET_ACCESS_KEY
  staging:
    access_key_id: YOUR_ACCESS_KEY
    secret_access_key: YOUR_SECRET_ACCESS_KEY

EOF
puts '=' * 80