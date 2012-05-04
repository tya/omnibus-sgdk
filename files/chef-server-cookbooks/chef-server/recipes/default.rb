#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
#

require 'openssl'

ENV['PATH'] = "/opt/chef-server/bin:/opt/chef-server/embedded/bin:#{ENV['PATH']}"

directory "/etc/chef-server" do
  owner "root"
  group "root"
  mode "0775"
  action :nothing
end.run_action(:create)

if File.exists?("/etc/chef-server/chef-server.json")
  Chef::Log.warn("Please move to /etc/chef-server/chef-server.rb for configuration - /etc/chef-server/chef-server.json is deprecated.")
else
  ChefServer[:node] = node
  if File.exists?("/etc/chef-server/chef-server.rb")
    ChefServer.from_file("/etc/chef-server/chef-server.rb")
  end
  node.consume_attributes(ChefServer.generate_config(node['fqdn']))
end

if File.exists?("/var/opt/chef-server/bootstrapped")
	node['chef_server']['bootstrap']['enable'] = false
end

# Create the Chef User
include_recipe "chef-server::users"

directory "/var/opt/chef-server" do
  owner "root"
  group "root"
  mode "0755"
  recursive true
  action :create
end

ruby_block "allow key creation" do
  block do
    system("chgrp #{node['chef_server']['user']['username']} /etc/chef-server")
  end
  not_if { File.exists?("/etc/chef-server/validation.pem") && File.exists?("/etc/chef-server/webui.pem") }
end

# Install our runit instance
include_recipe "runit"

# Configure Services
[ 
  "couchdb", 
  "rabbitmq", 
  "chef-solr",
  "chef-expander",
  "chef-server-api",
  "chef-server-webui",
  "nginx"
].each do |service|
  if node["chef_server"][service]["enable"]
    include_recipe "chef-server::#{service}"
  else
    include_recipe "chef-server::#{service}_disable"
  end
end

file "/etc/chef-server/chef-server-running.json" do
  owner node['chef_server']['user']['username']
  group "root"
  mode "0644"
  content Chef::JSONCompat.to_json_pretty({ "chef_server" => node['chef_server'].to_hash, "run_list" => node.run_list })
end

ruby_block "wait for certificate creation" do
  block do
    unless File.exists?("/etc/chef-server/validation.pem") && File.exists?("/etc/chef-server/webui.pem")
      raise "Still waiting on certificates!"
    end
  end
  retry_delay 10
  retries 20
end

directory "fix up /etc/chef-server" do
  path "/etc/chef-server"
  group "root"
end


file "/etc/chef-server/validation.pem" do
  owner "root"
  group node["chef_server"]['user']['username'] 
  mode "0640"
end

file "/etc/chef-server/webui.pem" do
  owner "root"
  group node["chef_server"]['user']['username'] 
  mode "0640"
end
