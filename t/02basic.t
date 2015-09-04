use strict;
use warnings;
use Test::More;
use Redis::ScriptCache;
use Redis;

if (not -f 'redis_connect_data') {
  plan(skip_all => "Need Redis test server host:port in the 'redis_connect_data' file");
  exit(0);
}

open my $fh, "<", "redis_connect_data" or die $!;
my $host = <$fh>;
$host =~ s/^\s+//;
chomp $host;
$host =~ s/\s+$//;

my $conn;
eval { $conn = Redis->new(server => $host); 1 }
or do {
  my $err = $@ || 'Zombie error';
  diag("Failed to connect to Redis server: $err. Not running tests");
  plan(skip_all => "Cannot connect to Redis server");
  exit(0);
};

eval {
  $conn->script_load("return 1");
  1
} or do {
  my $err = $@ || 'Zombie error';
  diag("Redis server does not appear to support Lua scripting. Not running tests");
  plan(skip_all => "Redis server does not support Lua scripting");
  exit(0);
};

plan tests => 6;

my $cache = Redis::ScriptCache->new(redis_conn => $conn);
isa_ok($cache, "Redis::ScriptCache");

my $sha = $cache->register_script("return 2");
ok(defined $sha && length($sha) == 40, "register_script returns SHA");

my $res = $cache->run_script($sha);
is($res, 2, "run script without args works");

$res = $cache->run_script($sha, [0]);
is($res, 2, "run script with args works");

$res = $cache->run_script(Digest::SHA1::sha1_hex("return 3"), [0], "return 3");
is($res, 3, "run script without pre-cached sha");

my @res = $cache->load_all_scripts(script_dir => 't/lua');
is_deeply(\@res, [ 'test' ], "load_scripts works for good scripts");
