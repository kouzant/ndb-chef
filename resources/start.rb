actions :start_if_not_running, :flex

attribute :name, :kind_of => String, :name_attribute => true

default_action :start_if_not_running
