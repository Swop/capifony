require "fileutils"
require "zlib"

namespace :database do
  namespace :dump do
    desc "Dumps remote database"
    task :remote do
      filename  = "#{application}.remote_dump.#{Time.now.to_i}.sql.gz"
      file      = "/tmp/#{filename}"
      sqlfile   = "#{application}_dump.sql"
      config    = ""

      run "cat #{current_path}/app/config/parameters.yml" do |ch, st, data|
        config = load_database_config data, symfony_env_prod
      end

      case config['database_driver']
      when "pdo_mysql", "mysql"
        run "mysqldump -u#{config['database_user']} --password='#{config['database_password']}' #{config['database_name']} | gzip -c > #{file}" do |ch, stream, data|
          puts data
        end
      when "pdo_pgsql", "pgsql"
        run "pg_dump -U #{config['database_user']} #{config['database_name']} --clean | gzip -c > #{file}" do |ch, stream, data|
          puts data
        end
      end


      FileUtils.mkdir_p("backups")
      get file, "backups/#{filename}"
      begin
        FileUtils.ln_sf(filename, "backups/#{application}.remote_dump.latest.sql.gz")
      rescue NotImplementedError # hack for windows which doesnt support symlinks
        FileUtils.cp_r("backups/#{filename}", "backups/#{application}.remote_dump.latest.sql.gz")
      end
      run "rm #{file}"
    end

    desc "Dumps local database"
    task :local do
      filename  = "#{application}.local_dump.#{Time.now.to_i}.sql.gz"
      tmpfile   = "backups/#{application}_dump_tmp.sql"
      file      = "backups/#{filename}"
      config    = load_database_config IO.read('app/config/parameters.yml'), symfony_env_local
      sqlfile   = "#{application}_dump.sql"

      FileUtils::mkdir_p("backups")
      case config['database_driver']
      when "pdo_mysql", "mysql"
        `mysqldump -u#{config['database_user']} --password=\"#{config['database_password']}\" #{config['database_name']} > #{tmpfile}`
      when "pdo_pgsql", "pgsql"
        `pg_dump -U #{config['database_user']} #{config['database_name']} --clean > #{tmpfile}`
      end

      File.open(tmpfile, "r+") do |f|
        gz = Zlib::GzipWriter.open(file)
        while (line = f.gets)
          gz << line
        end
        gz.flush
        gz.close
      end

      begin
        FileUtils.ln_sf(filename, "backups/#{application}.local_dump.latest.sql.gz")
      rescue NotImplementedError # hack for windows which doesnt support symlinks
        FileUtils.cp_r("backups/#{filename}", "backups/#{application}.local_dump.latest.sql.gz")
      end
      FileUtils.rm(tmpfile)
    end
  end

  namespace :move do
    desc "Dumps remote database, downloads it to local, and populates here"
    task :to_local do
      filename  = "#{application}.remote_dump.latest.sql.gz"
      config    = load_database_config IO.read('app/config/parameters.yml'), symfony_env_local
      sqlfile   = "#{application}_dump.sql"

      database.dump.remote

      f = File.new("backups/#{sqlfile}", "a+")
      gz = Zlib::GzipReader.new(File.open("backups/#{filename}", "r"))
      f << gz.read
      f.close

      case config['database_driver']
      when "pdo_mysql", "mysql"
        `mysql -u#{config['database_user']} --password=\"#{config['database_password']}\" #{config['database_name']} < backups/#{sqlfile}`
      when "pdo_pgsql", "pgsql"
        `psql -U #{config['database_user']} #{config['database_name']} < backups/#{sqlfile}`
      end
      FileUtils.rm("backups/#{sqlfile}")
    end

    desc "Dumps local database, loads it to remote, and populates there"
    task :to_remote do
      filename  = "#{application}.local_dump.latest.sql.gz"
      file      = "backups/#{filename}"
      sqlfile   = "#{application}_dump.sql"
      config    = ""

      database.dump.local

      upload(file, "/tmp/#{filename}", :via => :scp)
      run "gunzip -c /tmp/#{filename} > /tmp/#{sqlfile}"

      run "cat #{shared_path}/config/databases.yml" do |ch, st, data|
        config = load_database_config data, symfony_env_prod
      end

      case config['database_driver']
      when "pdo_mysql", "mysql"
        run "mysql -u#{config['database_user']} --password='#{config['database_password']}' #{config['database_name']} < /tmp/#{sqlfile}" do |ch, stream, data|
          puts data
        end
      when "pdo_pgsql", "pgsql"
        run "psql -U #{config['database_user']} #{config['database_name']} < /tmp/#{sqlfile}" do |ch, stream, data|
          puts data
        end
      end

      run "rm /tmp/#{filename}"
      run "rm /tmp/#{sqlfile}"
    end
  end
end
