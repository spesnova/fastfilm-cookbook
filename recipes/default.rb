#
# Author:: Seigo Uchida (<spesnova@gmail.com>)
# Cookbook Name:: fastfilm
# Recipe:: default
#
# Copyright (C) 2013 Seigo Uchida
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

gem_package "bundler" do
  action :install
  version "1.3.5"
end

user node["fastfilm"]["user"] do
  system true
end

# Setup database
if fastfilm_db = data_bag_item("fastfilm", "database")
  node.normal["fastfilm"]["user_password"]        = fastfilm_db["user_password"]
  node.normal["mysql"]["server_root_password"]   = fastfilm_db["root_password"]
  node.normal["mysql"]["server_repl_password"]   = fastfilm_db["repl_password"]
  node.normal["mysql"]["server_debian_password"] = fastfilm_db["debian_password"]
end

include_recipe "mysql::client"
include_recipe "mysql::ruby"
include_recipe "mysql::server"

service "mysqld" do
  supports :status => true, :restart => true
  action [ :enable, :start ]
end

connection_info = {
  :host => "localhost",
  :username => "root",
  :password => node["mysql"]["server_root_password"]
}

mysql_database node["fastfilm"]["database"] do
  connection connection_info
  action :create
end

mysql_database_user node["fastfilm"]["database_user"] do
  connection connection_info
  password node["fastfilm"]["user_password"]
  action :create
end

mysql_database_user node["fastfilm"]["database_user"] do
  connection connection_info
  database_name node["fastfilm"]["database"]
  privileges [:all]
  password node["fastfilm"]["user_password"]
  action :grant
end

# Setup firewall
template "/etc/sysconfig/iptables" do
  source "iptables.erb"
  owner "root"
  group "root"
  mode "0600"
  variables({:port => node["fastfilm"]["port"]})
  notifies :restart, "service[iptables]"
end

service "iptables" do
  supports :status => true, :restart => true, :reload => true
  action [:enable, :start]
end

# Making the directories for deploy
directory node["fastfilm"]["deploy_to"] do
  owner node["fastfilm"]["user"]
  group node["fastfilm"]["user"]
  mode "0755"
  recursive true
end

directory "#{node['fastfilm']['deploy_to']}/shared" do
  owner node["fastfilm"]["user"]
  group node["fastfilm"]["user"]
  mode "0755"
end

%w{ config log system pids cached-copy bundle }.each do |dir|
  directory "#{node['fastfilm']['deploy_to']}/shared/#{dir}" do
    owner node["fastfilm"]["user"]
    group node["fastfilm"]["user"]
    mode "0755"
    recursive true
  end
end

# Setup nginx
include_recipe "nginx"

file "/etc/nginx/sites-enabled/default" do
 action :delete
end

file "/etc/nginx/sites-enabled/000-default" do
  action :delete
end

%w{ default.conf  ssl.conf  virtual.conf }.each do |f|
  file "/etc/nginx/conf.d/#{f}" do
    action :delete
  end
end

service "nginx" do
 supports :status => true, :restart => true, :reload => true
end

template "#{node["fastfilm"]["deploy_to"]}/shared/config/fastfilm-nginx.conf" do
 user node["fastfilm"]["user"]
 group node["fastfilm"]["user"]
 source "fastfilm-nginx.conf.erb"
 variables(:host => node["fastfilm"]["host"],
           :base_path => node["fastfilm"]["deploy_to"],
           :http_port => node["fastfilm"]["port"],
           :backend_port => node["fastfilm"]["backend_port"])
 notifies :restart, "service[nginx]", :delayed
end

link "/etc/nginx/sites-available/fastfilm.conf" do
 to "#{node['fastfilm']['deploy_to']}/shared/config/fastfilm-nginx.conf"
end

link "/etc/nginx/sites-enabled/fastfilm.conf" do
 to "/etc/nginx/sites-available/fastfilm.conf"
end

# Setup unicorn
include_recipe "unicorn"

# TODO add notifies attribute that notify restart unicorn
unicorn_config "#{node['fastfilm']['deploy_to']}/shared/config/unicorn.rb" do
  listen({ node["unicorn"]["port"] => { :tcp_nodelay => true, :backlog => 100 }})
  #listen({ node["unicorn"]["port"] => "/opt/fastfilm/shared/pid/nginx-rails.sock" })
  worker_processes node["unicorn"]["worker_processes"]
  worker_timeout node["unicorn"]["worker_timeout"]
  preload_app node["unicorn"]["preload_app"]
  pid "#{node['fastfilm']['deploy_to']}/shared/pids/unicorn.pid"
  before_exec node["unicorn"]["before_exec"]
  before_fork node["unicorn"]["before_fork"]
  after_fork node["unicorn"]["after_fork"]
  stderr_path "#{node['fastfilm']['deploy_to']}/shared/log/unicorn.stderr.log"
  stdout_path "#{node['fastfilm']['deploy_to']}/shared/log/unicorn.stdout.log"
  copy_on_write node["unicorn"]["copy_on_write"]
  enable_stats node["unicorn"]["enable_stats"]
  notifies nil
end

# Insall and setup for rmagick
if node[:platform_family] == "rhel"
  %w{ ImageMagick ImageMagick-devel ipa-pgothic-fonts ffmpeg-devel sqlite-devel}.each do |pkg|
    package pkg
  end
end

# create ssh wrapper
directory "/tmp/private_code/.ssh" do
  owner node["fastfilm"]["user"]
  recursive true
end

cookbook_file "/tmp/private_code/wrap-ssh4git.sh" do
  source "wrap-ssh4git.sh"
  owner node["fastfilm"]["user"]
  mode "0700"
end

file "/tmp/private_code/.ssh/deploy.id_rsa" do
  owner node["fastfilm"]["user"]
  mode "0600"
  content data_bag_item("fastfilm", "deploy")["key"]
end

# Deploy the fastfilm app
deploy_revision node["fastfilm"]["deploy_to"] do
  action :deploy
  user node["fastfilm"]["user"]
  group node["fastfilm"]["group"]
  environment "RAILS_ENV" => "production"
  git_ssh_wrapper "/tmp/private_code/wrap-ssh4git.sh"

  # Checkout
  repo node["fastfilm"]["repo"]
  revision node["fastfilm"]["revision"]
  shallow_clone false
  enable_submodules true

  # Migrate
  before_migrate do
    [
      "#{node['fastfilm']['deploy_to']}/shared/config/database.yml",
      "#{release_path}/config/database.yml"
    ].each do |t|
      template t do
        source "database.yml.erb"
        owner node["fastfilm"]["user"]
        group node["fastfilm"]["user"]
        mode "0644"
        variables({
          :database => node["fastfilm"]["database"],
          :host     => "localhost",
          :username => node["fastfilm"]["database_user"],
          :password => node["fastfilm"]["user_password"],
          :encoding => "utf8"
        })
      end
    end
    execute "bundle install" do
      command <<-CMD
        bundle install \
        --path #{node["fastfilm"]["deploy_to"]}/shared/bundle \
        > /tmp/bundle.log
      CMD
      user node["fastfilm"]["user"]
      cwd release_path
      action :run
    end
    execute "asset precompile" do
      command "bundle exec rake assets:precompile RAILS_ENV=production"
      user node["fastfilm"]["user"]
      cwd release_path
      action :run
    end
  end
  symlink_before_migrate "config/database.yml" => "config/database.yml"
  migrate true
  migration_command <<-CMD
    bundle exec rake db:migrate --trace > /tmp/migration.log 2>&1
  CMD

  # Symlink
  purge_before_symlink %w{ log tmp/pids public/system }
  create_dirs_before_symlink %w{ tmp public config }
  symlinks "system" => "public/system",
           "pids"   => "tmp/pids",
           "log"    => "log",
           "config/configuration.yml" => "config/configuration.yml",
           "config/unicorn.rb" => "config/unicorn.rb"

  # Restart
  if ::File.exists?("#{node['fastfilm']['deploy_to']}/shared/pids/unicorn.pid`")
    restart_command <<-CMD
      kill -USR2 `cat #{node['fastfilm']['deploy_to']}/shared/pids/unicorn.pid`
    CMD
  end
end

execute "start unicorn" do
  command "bundle exec unicorn_rails -c config/unicorn.rb -D -E production"
  user "root"
  cwd "#{node["fastfilm"]["deploy_to"]}/current"
  not_if { ::File.exists?("#{node["fastfilm"]["deploy_to"]}/shared/pids/unicorn.pid") }
  action :run
end


## FIXME
%w{ bg_header.png bg_footer.png icon.png }.each do |f|
  link "#{node['fastfilm']['deploy_to']}/current/public/assets/#{f}" do
    to "#{node['fastfilm']['deploy_to']}/current/app/assets/images/#{f}"
  end
end
