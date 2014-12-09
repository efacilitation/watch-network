coffee = require 'gulp-coffee'

module.exports = (gulp) ->
  gulp.task 'build', ['build:src']

  gulp.task 'build:src', ->
    gulp.src(['src/!(*.spec)*.coffee'])
      .pipe(
        coffee()
      )
      .pipe(
        gulp.dest './build/src'
      )
