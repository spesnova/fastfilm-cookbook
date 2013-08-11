#
# Author:: Seigo Uchida (<spesnova@gmail.com>)
# Cookbook Name:: fastfilm
# Attributes:: default
#
# Copyright (C) 2013 Seigo Uchida (<spesnova@gmail.com>)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

default["fastfilm"]["user"]         = "fastfilm"
default["fastfilm"]["group"]        = "fastfilm"
default["fastfilm"]["deploy_to"]    = "/opt/fastfilm"
default["fastfilm"]["repo"]         = "git@github.com:spesnova/fastfilm.git"
default["fastfilm"]["revision"]     = "83fb547e80c65b33390e70ba574a0c55b78c0ed5"
default["fastfilm"]["port"]         = "80"
default["fastfilm"]["backend_port"] = "#{node['fastfilm']['deploy_to']}/shared/pids/nginx-rails.sock"
default["fastfilm"]["domain"]       = "fastfilm.info"

# Unicorn setting
default["unicorn"]["port"]             = default["fastfilm"]["backend_port"]
default["unicorn"]["options"]          = { :tcp_nodelay => true, :backlog => 100 }
default["unicorn"]["worker_processes"] = [node[:cpu][:total].to_i * 4, 8].min
default["unicorn"]["worker_timeout"]   = "30"
default["unicorn"]["preload_app"]      = true
default["unicorn"]["before_exec"]      = nil
default["unicorn"]["before_fork"]      = <<-BLOCK
old_pid = "#{node['fastfilm']['deploy_to']}/current" + '/tmp/pids/unicorn.pid.oldbin'
  if ::File.exists?(old_pid) && server.pid != old_pid
    begin
      process.kill("QUIT", ::File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      # someone else did our job for us
    end
  end
BLOCK
default["unicorn"]["after_fork"]       = <<-BLOCK
ActiveRecord::Base.establish_connection

  begin
    uid, gid = Process.euid, Process.egid
    user, group = "#{node['fastfilm']['user']}", "#{node['fastfilm']['group']}"
    target_uid = Etc.getpwnam(user).uid
    target_gid = Etc.getgrnam(group).gid
    worker.tmp.chown(target_uid, target_gid)
    if uid != target_uid || gid != target_gid
      Process.initgroups(user, target_gid)
      Process::GID.change_privilege(target_gid)
      Process::UID.change_privilege(target_uid)
    end
  rescue => e
    raise e
  end
BLOCK
default["unicorn"]["enable_stats"]     = false
default["unicorn"]["copy_on_write"]    = false

# database setting
default["fastfilm"]["database"]      = "fastfilm"
default["fastfilm"]["database_user"] = "fastfilm"
# You can specify this password in role or data bags.
# Note!! data bags attribute takes top precedence.
default["fastfilm"]["user_password"] = nil
default['mysql']['tunable']['character-set-server'] = "utf8"
# The following three passwords is made automaticaly by mysql cookbook.
# Also You can specify these in role or data bags.
# Note!! data bags attribute takes top precedence.
default["mysql"]["server_root_password"]   = nil
default["mysql"]["server_repl_password"]   = nil
default["mysql"]["server_debian_password"] = nil
