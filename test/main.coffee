fs                    = require 'fs'
gutil                 = require 'gulp-util'

#expect = require 'expect'


describe 'gulp-commonjs-wrap', ->

  it 'should ', (next) ->

    gulpWatchNetwork = require '../'
    gulpWatchNetwork
      port: 4000
      host: '10.23.42.1'
