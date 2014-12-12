sinonChai = require 'sinon-chai'
chai = require 'chai'
chai.use sinonChai

global.expect = chai.expect
global.sinon = require 'sinon'
global.sandbox = sinon.sandbox.create()
global.mockery = require 'mockery'

mockery.enable
  useCleanCache: true
  warnOnUnregistered: false


global.afterEach ->
  mockery.resetCache()
  mockery.deregisterAll()
  sandbox.restore()