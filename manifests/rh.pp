class fileauth::rh {
  file { '/var/lib/cdbrepo':
    ensure => directory,
    mode => 770, owner => root, group => puppet,
  }

  file { '/etc/passwd.M':
    content => generate('/mnt/puppetfiles/scripts/cdbrepo.pl', "--retrieve", "$hostname"),
    mode => 0400, owner => root, group => root,
    notify => Exec['mkcpasswd'],
    require => File['/var/lib/cdbrepo'],
  }

  ccbp::remotefile{ '/etc/mkcpasswd.pl': modulename => 'fileauth', mode => 0755 }

  exec { 'mkcpasswd':
    command => '/etc/mkcpasswd.pl',
    cwd => '/etc',
    refreshonly => true,
    require => File['/etc/mkcpasswd.pl'],
  }
}
