libdir = File.expand_path("../../lib", __FILE__)
$LOAD_PATH.unshift libdir unless $LOAD_PATH.include? libdir

testdir = File.dirname(__FILE__)
$LOAD_PATH.unshift testdir unless $LOAD_PATH.include? testdir
