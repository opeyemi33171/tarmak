class vault_server::service (
  Optional[String] $vault_unsealer_kms_key_id = $vault_server::vault_unsealer_kms_key_id,
  Optional[String] $vault_unsealer_ssm_key_prefix = $vault_server::vault_unsealer_ssm_key_prefix,
  Optional[String] $vault_unsealer_key_dir = $vault_server::vault_unsealer_key_dir,
  String $region = $vault_server::region,
  String $user = 'root',
  String $group = 'root',
  String $assets_service_name = 'vault-assets',
  String $unsealer_service_name = 'vault-unsealer',
  String $init_service_name = 'vault-init',
  String $service_name = 'vault',
)
{

  if $vault_server::vault_tls_cert_path == '' {
    $vault_tls_cert_path = undef
  } else {
    $vault_tls_cert_path = $vault_server::vault_tls_cert_path
  }

  if $vault_server::vault_tls_ca_path == '' {
    $vault_tls_ca_path = undef
  } else {
    $vault_tls_ca_path = $vault_server::vault_tls_ca_path
  }

  if $vault_server::vault_tls_key_path == '' {
    $vault_tls_key_path = undef
  } else {
    $vault_tls_key_path = $vault_server::vault_tls_key_path
  }

  if $vault_unsealer_kms_key_id and $vault_unsealer_ssm_key_prefix {
      $dev_mode = false
  } else {
      $dev_mode = true
  }

  exec { "${service_name}-systemctl-daemon-reload":
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
    path        => defined('$::path') ? {
      default => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin',
      true    => $::path
    },
  }

  file { "${::vault_server::systemd_dir}/${assets_service_name}.service":
    ensure  => file,
    content => template('vault_server/vault-assets.service.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0644',
    notify  => Exec["${service_name}-systemctl-daemon-reload"]
  } ~> service { "${assets_service_name}.service":
    ensure  => 'running',
    enable  => false,
    require => Exec["${service_name}-systemctl-daemon-reload"],
  }

  file { "${::vault_server::systemd_dir}/${unsealer_service_name}.service":
    ensure  => file,
    content => template('vault_server/vault-unsealer.service.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0644',
    notify  => Exec["${service_name}-systemctl-daemon-reload"],
  } ~> service { "${unsealer_service_name}.service":
    ensure  => 'running',
    enable  => true,
    require => Exec["${service_name}-systemctl-daemon-reload"],
  }

  file { "${::vault_server::systemd_dir}/${service_name}.service":
    ensure  => file,
    content => template('vault_server/vault.service.erb'),
    owner   => $user,
    group   => $group,
    mode    => '0644',
    notify  => Exec["${service_name}-systemctl-daemon-reload"]
  } ~> service { "${service_name}.service":
    ensure  => 'running',
    enable  => true,
    require => Exec["${service_name}-systemctl-daemon-reload"],
  }


  if $dev_mode {

    file { "${vault_server::bin_dir}/vault-init.sh":
      ensure  => file,
      content => file('vault_server/vault-init.sh'),
      owner   => $user,
      group   => $group,
      mode    => '0744',
    } -> file { "${::vault_server::systemd_dir}/${init_service_name}.service":
      ensure  => file,
      content => template('vault_server/vault-init.service.erb'),
      owner   => $user,
      group   => $group,
      mode    => '0644',
      notify  => Exec["${service_name}-systemctl-daemon-reload"]
    } ~> service { "${init_service_name}.service":
      ensure  => 'running',
      enable  => true,
      require => Exec["${service_name}-systemctl-daemon-reload"],
    }
  }
}
