class fileauth::server::rh {
  cron { 'updatecdbrepo':
    command => "$pm_scripts/cdbrepo.pl --update > /dev/null",
    user => puppet,
    minute => [ 0,15,30,45 ],
    require => File['/var/lib/cdbrepo'],
  }

  file { "$pm_filesystem/from_udb/cdb":
    ensure => directory,
    mode => 770, owner => puppet, group => puppet,
  }

  file { '/var/lib/cdbrepo':
    ensure => directory,
    mode => 770, owner => root, group => puppet,
  }
}

