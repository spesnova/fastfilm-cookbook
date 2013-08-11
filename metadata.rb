name             'fastfilm'
maintainer       'Seigo Uchida'
maintainer_email 'spesnova@gmail.com'
license          'Apache 2.0'
description      'Installs/Configures fastfilm'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.1.2'

%W{ centos }.each do |os|
  supports os
end

%W{ git mysql database iptables unicorn nginx }.each do |cb|
  depends cb
end
