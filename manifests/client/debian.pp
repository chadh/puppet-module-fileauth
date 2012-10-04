class fileauth::client::debian {
  file { '/etc/passwd.M':
    content => generate("$pm_scripts/cdbrepo.pl", "--retrieve", "$hostname.passwd"),
    mode => 0400, owner => root, group => root,
    notify => Exec['mkcpasswd'],
  }

  ccbp::remotefile{ '/etc/mkcpasswd.pl': modulename => 'fileauth', mode => 0700 }

  exec { 'mkcpasswd':
    command => '/etc/mkcpasswd.pl',
    cwd => '/etc',
    refreshonly => true,
    require => File['/etc/mkcpasswd.pl'],
  }

  file { '/etc/group.M':
    content => generate("$pm_scripts/cdbrepo.pl", "--retrieve", "ALL.group"),
    mode => 0400, owner => root, group => root,
    notify => Exec['mkcgroup'],
  }

  ccbp::remotefile{ '/etc/mkcgroup.pl': modulename => 'fileauth', mode => 0700 }

  exec { 'mkcgroup':
    command => '/etc/mkcgroup.pl',
    cwd => '/etc',
    refreshonly => true,
    require => File['/etc/mkcgroup.pl'],
  }

}
