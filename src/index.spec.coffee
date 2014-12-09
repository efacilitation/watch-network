fs = require 'fs'

chai = require 'chai'
expect = chai.expect

sinonChai = require 'sinon-chai'
sinon = require 'sinon'
chai.use sinonChai

sandbox = sinon.sandbox.create()
mockery = require 'mockery'

mockery.enable
  useCleanCache: true
  warnOnUnregistered: false



describe 'WatchNetwork', ->

  afterEach ->
    mockery.resetCache()
    mockery.deregisterAll()
    sandbox.restore()


  socketStub = null
  WatchNetwork = null
  netMockery = null
  beforeEach ->
    socketStub =
      on: sandbox.stub()
      end: sandbox.stub()
    netMockery =
      connect: sandbox.stub().returns socketStub

    mockery.registerMock 'net', netMockery
    WatchNetwork = require './'


  describe '#initialize', ->
    it 'should execute net.connect when starting', ->
      WatchNetwork().initialize()
      expect(netMockery.connect).to.have.been.called


    it 'should connect to the given host and port', ->
      WatchNetwork(
        host: 'test'
        port: '1337'
      ).initialize()

      expect(netMockery.connect).to.have.been.calledWithExactly
        host: 'test'
        port: '1337'
        sinon.match.func


  describe 'EventEmitter', ->
    beforeEach ->
      fileBuffer = toString: ->
        """
        {
          "modified": ["/path/to/modified/file"],
          "added": ["/path/to/added/file"],
          "removed": ["/path/to/removed/file"]
        }
        """

      socketStub.on.withArgs('data').yields fileBuffer


    it 'should emit an event on file change', (done) ->
      watchNetwork = WatchNetwork()
      watchNetwork.on 'changed', (files) ->
        expect(files).to.deep.equal [
          '/path/to/modified/file',
          '/path/to/added/file',
          '/path/to/removed/file'
        ]
        done()

      watchNetwork.initialize()
