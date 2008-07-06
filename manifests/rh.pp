class fileauth::rh {
  file { '/etc/passwd.M':
    content => generate('/mnt/puppetfiles/scripts/cdbrepo.pl', "retrieve", "$hostname"),
    ensure => present,
    mode => 0400, owner => root, group => root,
    notify => Exec['mkcpasswd'],
  }

  ccbp::remotefile{ '/etc/mkcpasswd.pl': modulename => 'fileauth', mode => 0755 }

  exec { 'mkcpasswd':
    command => '/etc/mkcpasswd.pl',
    cwd => '/etc',
    refreshonly => true,
    require => File['/etc/mkcpasswd.pl'],
  }
}
