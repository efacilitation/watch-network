gulp = require 'gulp'
runSequence = require 'run-sequence'


gulp.task 'watch', ->
  gulp.watch [
    'src/*.coffee'
  ], [
    'spec'
  ]

gulp.task 'spec', (next) ->
  runSequence 'build', 'spec:server', next

require('./gulp/spec')(gulp)
require('./gulp/build')(gulp)
