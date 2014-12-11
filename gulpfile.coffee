gulp  = require 'gulp'
gutil = require 'gulp-util'
runSequence = require 'run-sequence'

gulp.on 'err', (e) ->
gulp.on 'task_err', (e) ->
  if process.env.CI
    gutil.log e
    process.exit 1

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
