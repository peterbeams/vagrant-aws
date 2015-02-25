require 'vagrant-aws/util/network_adapters'

module VagrantPlugins
  module AWS
    module Action      
      class RegisterAdditionalNetworkInterfaces
        include NetworkAdapter

        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new("vagrant_aws::action::network_adapters_register")          
        end
        
        def call(env)

          @app.call(env)

          interfaces = env[:machine].provider_config.additional_network_interfaces

          interfaces.each_with_index do |intf, i|
            env[:ui].info(I18n.t("vagrant_aws.creating_network_interface"))
            env[:ui].info(" -- Device Index: #{intf[:device_index]}")
            env[:ui].info(" -- Subnet ID: #{intf[:subnet_id]}")
            env[:ui].info(" -- Security Groups: #{intf[:security_groups]}")
            env[:ui].info(" -- IP: #{intf[:private_ip_address]}")
          	register_adapter env, intf[:device_index], intf[:subnet_id], intf[:security_groups], intf[:private_ip_address], env[:machine].id

            if env[:machine].config.vm.guest.eql?(:windows)

              install_script_name = "adapter-#{intf[:device_index]}.ps1"
              script_tmp_path = env[:tmp_path].join("#{Time.now.to_i.to_s}-#{install_script_name}")
              File.open(script_tmp_path, 'w') do |f|
                f.puts <<-EOH.gsub(/^\s{18}/, '')                  
                  do
                  {
                      "Waiting for network adapter to become available..."
                      sleep 1
                  } until (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPAddress -and $_.IPAddress[0] -eq "#{intf[:private_ip_address]}" })                  
                  netsh interface ip set address name="Local Area Connection #{intf[:device_index] + 1}" source=static address=#{intf[:private_ip_address]} mask=255.255.255.0 gateway=none
                EOH
              end

              env[:machine].communicate.tap do |comm|                                          
                comm.upload(script_tmp_path, install_script_name)
                install_cmd = "powershell.exe .\\#{install_script_name}"
                comm.sudo(install_cmd, { shell: 'cmd' }) do |type, data|
                  if [:stderr, :stdout].include?(type)
                    next if data =~ /stdin: is not a tty/
                    env[:ui].info(data)
                  end
                end
              end
            end
            
          end
        end

      end
    end
  end
end