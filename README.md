 [![Build Status](https://travis-ci.org/efacilitation/gulp-watch-network.svg?branch=master)](https://travis-ci.org/efacilitation/gulp-watch-network)

## Information

<table>
<tr>
<td>Package</td><td>gulp-watch-network</td>
</tr>
<tr>
<td>Description</td>
<td>Watch File Events received over the Network using net.connect</td>
</tr>
</table>

Based on the Listen Feature "[Forwarding file events over TCP](https://github.com/guard/listen#forwarding-file-events-over-tcp)", this plugin will connect to a Listen broadcaster as a receiver and watch for File Events. Upon receiving a File Event it will execute `tasks` based on `patterns`. This can be useful for virtualized development environments when file events are unavailable, as is the case with [Vagrant](https://github.com/mitchellh/vagrant) / [VirtualBox](https://www.virtualbox.org).

## Usage

First, install `gulp-watch-network` as a development dependency:

```shell
npm install --save-dev gulp-watch-network
```

Then, add it to your `gulpfile.js`:

```javascript
watchNetwork = require("gulp-watch-network");

gulp.task('watch', function() {

  watchNetwork: {
    host: '127.0.0.1'
    configs: [
      {
        tasks: 'scripts'
        onLoad: true
      }, {
        patterns: 'lib/*.coffee'
        tasks: 'specs'
      }
  }
});

```


## License
Licensed under the MIT license.
