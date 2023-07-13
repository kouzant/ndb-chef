backup_directory = "#{node['ndb']['local_backup_dir']}/#{File.basename(node['ndb']['restore']['tarball'], ".tar.gz")}"
private_ip=my_private_ip()
ndb_connectstring()
mgm_connection = node['ndb']['connectstring']
should_run = private_ip.eql?(node['ndb']['mysqld']['private_ips'].sort[0])
mysql_cli = "#{node['ndb']['scripts_dir']}/mysql-client.sh"
rebuild_indexes_check = "#{Chef::Config['file_cache_path']}/rondb_rebuild_indexes_#{node['install']['version']}_#{node['ndb']['version']}"

bash 'Rebuild indexes' do
    user 'root'
    group 'root'
    code <<-EOH
        set -e
        #{node['ndb']['scripts_dir']}/restore_backup.sh ndb-restore -p #{backup_directory} -n 1 -b #{node['ndb']['restore']['backup_id']} -c #{mgm_connection} -m REBUILD-INDEXES
        touch #{rebuild_indexes_check}
    EOH
    # Add this check to avoid re-running this block in case one of the following steps
    # fail and the recipe is retried
    not_if { ::File.exists?(rebuild_indexes_check) }
    only_if { should_run }
    only_if { rondb_restoring_backup() }
end

bash 'Restore SQL' do
    user 'root'
    group 'root'
    code <<-EOH
        set -e
        # Drop the procedures and view in case we retry
        #{mysql_cli} -e "DROP PROCEDURE IF EXISTS hops.simpleproc"
        #{mysql_cli} -e "DROP PROCEDURE IF EXISTS hops.flyway"
        #{mysql_cli} -e "DROP PROCEDURE IF EXISTS airflow.create_idx"
        #{mysql_cli} -e "DROP VIEW IF EXISTS hopsworks.users_groups"

        #{node['ndb']['scripts_dir']}/restore_backup.sh restore-schema -p #{backup_directory}
    EOH
    only_if { should_run }
    only_if { rondb_restoring_backup() }
end

hopsworks_consul = consul_helper.get_service_fqdn("hopsworks.glassfish")
bash 'Remove host certificates' do
    user 'root'
    group 'root'
    code <<-EOH
        set -e
        #{mysql_cli} -e "DELETE FROM hopsworks.pki_certificate WHERE subject REGEXP '^C=.+ST=Sweden.+CN.+' AND status=1"
        #{mysql_cli} -e "UPDATE hopsworks.pki_certificate SET status=1 WHERE subject REGEXP '^C=.+ST=Sweden.+CN.+'"

        #{mysql_cli} -e "DELETE FROM hopsworks.pki_certificate WHERE subject REGEXP '^CN=#{hopsworks_consul}.+' AND status=1"
        #{mysql_cli} -e "UPDATE hopsworks.pki_certificate SET status=1 WHERE subject REGEXP '^CN=#{hopsworks_consul}.+'"
    EOH
    only_if { should_run }
    only_if { rondb_restoring_backup() }
end

##
## NOTE: This should always be the last step in this recipe
##
file rebuild_indexes_check do
    action :delete
end