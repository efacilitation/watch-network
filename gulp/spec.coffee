gutil = require 'gulp-util'
spawn = require('child_process').spawn

module.exports = (gulp) ->
  mochaProcess = null
  gulp.task 'spec:server', (next) ->
    glob = ['src/*.spec.coffee']
    options = [
      '--compilers'
      'coffee:coffee-script/register'
      '--reporter'
      'spec'
    ]
    if mochaProcess and mochaProcess.kill
      mochaProcess.kill()
    mochaProcess = spawn(
      'node_modules/.bin/mocha'
      options.concat(glob)
      {}
      next
    )
    mochaProcess.stdout.on 'data', (data) ->
      process.stdout.write data.toString()
    mochaProcess.stderr.on 'data', (data) ->
      process.stderr.write data.toString()
    mochaProcess.on 'close', (code) ->
      if code is 0
        gutil.log gutil.colors.green "Finished: mocha server"
        next()
      else
        errorMessage = "Failed: mocha server"
        gutil.log gutil.colors.red errorMessage
        gutil.beep()
        if process.env.CI
          process.exit 1
        else
          next()

    return
