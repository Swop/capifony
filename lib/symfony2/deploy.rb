# Overrided Capistrano tasks
namespace :deploy do
  desc <<-DESC
    Sets permissions for writable_dirs folders as described in the Symfony documentation
    (http://symfony.com/doc/master/book/installation.html#configuration-and-setup)
  DESC
  task :set_permissions, :roles => :app do
    if writable_dirs && permission_method
      dirs = []

      writable_dirs.each do |link|
        if shared_children && shared_children.include?(link)
          absolute_link = shared_path + "/" + link
        else
          absolute_link = latest_release + "/" + link
        end

        dirs << absolute_link
      end

      methods = {
        :chmod => "#{try_sudo} chmod +a \"#{webserver_user} allow delete,write,append,file_inherit,directory_inherit\" %s",
        :acl   => "#{try_sudo} setfacl -dR -m u:#{webserver_user}:rwx %s",
        :chown => "#{try_sudo} chown #{webserver_user} %s"
      }

      if methods[permission_method]
        pretty_print "--> Setting permissions"

        if use_sudo
          run sprintf(methods[permission_method], dirs.join(' '))
        elsif permission_method == :chown
          puts "    You can't use chown method without sudoing"
        else
          dirs.each do |dir|
            is_owner = (capture "`echo stat #{dir} -c %U`").chomp == user
            if is_owner && permission_method != :chown
              run sprintf(methods[permission_method], dir)
            else
              puts "    #{dir} is not owned by #{user} or you are using 'chown' method without 'use_sudo'"
            end
          end
        end
        puts_ok
      else
        puts "    Permission method '#{permission_method}' does not exist.".yellow
      end
    end
  end

  desc "Symlinks static directories and static files that need to remain between deployments"
  task :share_childs, :except => { :no_release => true } do
    if shared_children
      pretty_print "--> Creating symlinks for shared directories"

      shared_children.each do |link|
        run "mkdir -p #{shared_path}/#{link}"
        run "if [ -d #{release_path}/#{link} ] ; then rm -rf #{release_path}/#{link}; fi"
        run "ln -nfs #{shared_path}/#{link} #{release_path}/#{link}"
      end

      puts_ok
    end

    if shared_files
      pretty_print "--> Creating symlinks for shared files"

      shared_files.each do |link|
        link_dir = File.dirname("#{shared_path}/#{link}")
        run "mkdir -p #{link_dir}"
        run "touch #{shared_path}/#{link}"
        run "ln -nfs #{shared_path}/#{link} #{release_path}/#{link}"
      end

      puts_ok
    end
  end

  desc "Updates latest release source path"
  task :finalize_update, :except => { :no_release => true } do
    run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)

    pretty_print "--> Creating cache directory"

    run "if [ -d #{latest_release}/#{cache_path} ] ; then rm -rf #{latest_release}/#{cache_path}; fi"
    run "mkdir -p #{latest_release}/#{cache_path} && chmod -R 0777 #{latest_release}/#{cache_path}"
    run "chmod -R g+w #{latest_release}/#{cache_path}"

    puts_ok

    share_childs

    if fetch(:normalize_asset_timestamps, true)
      stamp = Time.now.utc.strftime("%Y%m%d%H%M.%S")
      asset_paths = asset_children.map { |p| "#{latest_release}/#{p}" }.join(" ")

      if asset_paths.chomp.empty?
        puts "    No asset paths found, skipped".yellow
      else
        pretty_print "--> Normalizing asset timestamps"

        run "find #{asset_paths} -exec touch -t #{stamp} {} ';' >& /dev/null || true", :env => { "TZ" => "UTC" }
        puts_ok
      end
    end
  end

  desc <<-DESC
    Deploys and starts a `cold' application. This is useful if you have not \
    deployed your application before.
  DESC
  task :cold do
    update
    start
  end

  desc "Deploys the application and runs the test suite"
  task :testall, :except => { :no_release => true } do
    update_code
    create_symlink
    run "cd #{latest_release} && phpunit -c #{app_path} src"
  end

  desc "Runs the Symfony2 migrations"
  task :migrate do
    if model_manager == "doctrine"
      symfony.doctrine.migrations.migrate
    else
      if model_manager == "propel"
        puts "    Propel doesn't have built-in migration for now".yellow
      end
    end
  end
end
