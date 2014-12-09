require 'listen'
require 'daemons'

basedir = File.dirname(File.expand_path(__FILE__))
watchdirs = [
  File.join(basedir, 'src'),
  File.join(basedir, 'static/locales')
]

Daemons.run_proc('listen_fswatch') do
  listener = Listen.to watchdirs, forward_to: '10.23.42.1:4000'
  listener.start

  sleep
end
