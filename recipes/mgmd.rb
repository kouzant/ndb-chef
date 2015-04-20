require File.expand_path(File.dirname(__FILE__) + '/get_ndbapi_addrs')
libpath = File.expand_path '../../../kagent/libraries', __FILE__
require File.join(libpath, 'inifile')

ndb_connectstring()
#generate_etc_hosts()

directory node[:ndb][:mgm_dir] do
  owner node[:ndb][:user]
  group node[:ndb][:user]
  mode "755"
  recursive true
end

found_id=-1
id=node[:mgm][:id]
my_ip = my_private_ip()

for mgm in node[:ndb][:mgmd][:private_ips]
  if my_ip.eql? mgm
    Chef::Log.info "Found matching IP address in the list of mgmd nodes: #{mgm}. ID= #{id}"
    found_id = id
  end
  id += 1
end 
Chef::Log.info "Found ID IS: #{found_id}"
if found_id == -1
  raise "Could not find matching IP address #{my_ip} in the list of mgmd nodes: " + node[:ndb][:mgmd][:private_ips].join(",")
end

#hostId="mgmd#{found_id}" 
#generate_hosts(hostId, my_ip)


for script in node[:mgm][:scripts] do
  template "#{node[:ndb][:scripts_dir]}/#{script}" do
    source "#{script}.erb"
    owner "root"
    group "root"
    mode 0655
    variables({ :node_id => found_id })
  end
end 

service "ndb_mgmd" do
  supports :restart => true, :stop => true, :start => true, :status => true
  action :nothing
end

template "/etc/init.d/ndb_mgmd" do
  source "ndb_mgmd.erb"
  owner node[:ndb][:user]
  group node[:ndb][:user]
  mode 0754
  variables({ :node_id => found_id })
  notifies :enable, "service[ndb_mgmd]"
end

# Need to call get_ndbapi_addrs to set them before instantiating config.ini
get_ndbapi_addrs()

template "#{node[:ndb][:root_dir]}/config.ini" do
  source "config.ini.erb"
  owner node[:ndb][:user]
  group node[:ndb][:user]
  mode 0644
  variables({
              :num_client_slots => node[:ndb][:num_ndb_slots_per_client].to_i
            })
  notifies :restart, "service[ndb_mgmd]", :immediately
end


  if node[:kagent][:enabled] == "true"
   mgm_id = found_id + (node[:mgm][:id]-1)

    kagent_config "mgmserver" do
      service "NDB"
      start_script "#{node[:ndb][:scripts_dir]}/mgm-server-start.sh"
      stop_script  "#{node[:ndb][:scripts_dir]}/mgm-server-stop.sh"
      log_file "#{node[:ndb][:log_dir]}/ndb_#{mgm_id}_out.log"
      pid_file "#{node[:ndb][:log_dir]}/ndb_#{mgm_id}.pid"
      config_file "#{node[:ndb][:root_dir]}/config.ini"
      command "ndb_mgm"
      command_user "root"
      command_script "#{node[:ndb][:scripts_dir]}/mgm-client.sh"
    end
  end

ndb_start "ndb_mgmd" do
end

#
# Put public key of this mgmd-host in .ssh/authorized_keys of all ndb_mgdt nodes
#
package "expect" do
end

homedir = node[:ndb][:user].eql?("root") ? "/root" : "/home/#{node[:ndb][:user]}"

template "#{Chef::Config[:file_cache_path]}/expect-ssh-keygen.sh" do
  source "expect-ssh-keygen.sh.erb"
  owner node[:ndb][:user]
  group node[:ndb][:user]
  mode 0755
  variables({
              :homedir => homedir
            })
end

Chef::Log.info "Home dir is #{homedir}. Generating ssh keys..."
bash "generate-ssh-keypair-mgmserver" do
 user node[:ndb][:user]
  code <<-EOF
#      #{Chef::Config[:file_cache_path]}/expect-ssh-keygen.sh
      ssh-keygen -b 2048 -t rsa -q -N ""
  EOF
 not_if { ::File.exists?( "#{homedir}/.ssh/id_rsa" ) }
end


openssh_pubkey = ""
ruby_block "Check if CURBID Web Manager needs installation" do
  block do

    if File.exists?("#{homedir}/.ssh/id_rsa.pub")
      # Read the CWM version from file.
      f = File.open("#{homedir}/.ssh/id_rsa.pub")

      f.each do |line|
         openssh_pubkey += line
      end

      f.close
    end
  end
end

kagent_param "/tmp" do
  executing_cookbook "ndb"
  executing_recipe "mgmd"
  cookbook "ndb"
  recipe "mgmd"
  param "public_key"
  value "#{openssh_pubkey}"
end


