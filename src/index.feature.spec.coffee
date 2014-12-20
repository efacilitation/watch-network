fs  = require 'fs'
del = require 'del'

{spawn} = require 'child_process'

describe 'WatchNetwork Feature', ->
  watch = null
  listenProcess = null
  beforeEach (done) ->
    if fs.existsSync './tmp'
      del.sync './tmp', force: true
    fs.mkdirSync './tmp'

    listenProcess = spawn "listen", ["-d", "./tmp"]
    setTimeout ->
      done()
    , 500


  afterEach (done) ->
    watch.stop()
    listenProcess.on 'close', ->
      setTimeout ->
        del.sync './tmp', force: true
        done()
      , 500
    listenProcess.kill 'SIGTERM'


  it 'should execute tasks based on file patterns', (done) ->
    niftyTaskCalled = false

    gulp = require 'gulp'
    gulp.task 'nifty', (next) ->
      niftyTaskCalled = true
      next()

    WatchNetwork = require './'
    watch = WatchNetwork
      gulp: gulp
      rootFile: './tmp/.root'
      configs: [
        {
          patterns: 'file.ext'
          tasks: 'foo'
        }
        {
          patterns: 'file.ext'
          tasks: 'nifty'
        }
      ]

    watch.on 'changed', (files) ->
      niftyIndex = files.indexOf 'file.ext'
      if niftyIndex > -1
        expect(files[niftyIndex]).to.equal 'file.ext'
        expect(niftyTaskCalled).to.be.true
        done()

    watch.task 'foo', (changedFile, callback) ->
      expect(changedFile).to.equal 'file.ext'
      callback()

    watch.task 'nifty', (changedFile, callback) ->
      expect(changedFile).to.equal 'file.ext'
      callback()

    watch.initialize ->
      fs.writeFileSync './tmp/file.ext'


  it 'should execute the tasks in series', (done) ->
    firstTaskCalled = false
    secondTaskCalled = false

    gulp = require 'gulp'
    gulp.task 'first', (next) ->
      firstTaskCalled = true
      setTimeout ->
        expect(secondTaskCalled).to.be.false
        next()
      , 250

    gulp.task 'second', ->
      secondTaskCalled = true
      expect(firstTaskCalled).to.be.true
      done()


    WatchNetwork = require './'
    watch = WatchNetwork
      gulp: gulp
      rootFile: './tmp/.root'
      configs: [
        {
          patterns: 'foo'
          tasks: ['first', 'second']
        }
      ]

    watch.initialize ->
      fs.writeFileSync './tmp/foo'
