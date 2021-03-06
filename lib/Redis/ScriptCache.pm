package Redis::ScriptCache;
use strict;
use warnings;

our $VERSION = '0.01';

use Digest::SHA1 qw(sha1_hex);

use Class::XSAccessor {
    constructor => 'new',
    getters => [qw(redis_conn)],
};

sub register_script {
    my ($self, $tmp, $sha) = @_; # sha optional
    my $script = ref($tmp) ? $tmp : \$tmp;

    if (defined $sha) {
      $sha = lc($sha);
    }
    else {
      $sha = sha1_hex($$script);
    }
    return $sha if exists $self->{$sha};

    my $conn = $self->redis_conn
        or die "Need Redis connection to register script";

    my $rv;
    eval {
        ($rv) = $conn->script_exists($sha)
    };

    $conn->script_load($$script) if not $rv;
    $self->{$sha} = $script;

    return $sha;
}

sub run_script {
    my ($self, $sha, $args, $script) = @_; # script optional
    
    if (defined $script and not exists $self->{$sha}) {
        $self->register_script($script, $sha);
    }

    my $conn = $self->redis_conn;
    return $conn->evalsha($sha, ($args ? (@$args) : (0)));
}

1;

__END__

=head1 NAME

Redis::ScriptCache - Cached Lua scripts on a Redis server

=head1 SYNOPSIS

  use Redis;
  use Redis::ScriptCache;
  
  my $conn = Redis->new(server => ...);
  my $cache = Redis::ScriptCache->new(redis_conn => $conn);
  
  # some Lua script to execute on the server
  my $script = q{
    local x = redis.call('get', KEYS[1]);
    redis.call('set', 'temp', x);
    return x;
  };
  my $script_sha = $cache->register_script($script);
  
  # later:
  my ($value) = $cache->run_script($script_sha, [1, "somekey"]);

=head1 DESCRIPTION

Recent versions of Redis can execute Lua scripts on the server.
This is appears to be the most effective and efficient way to group
interactions with Redis atomically. In order to avoid having to
re-transmit (and compile) the scripts themselves on every request,
Redis has a set of commands related to executing previously seen
scripts again using the SHA-1 as identification.

This module offers a way to avoid re-transmission of the full script
without checking for script existence on the server manually each time.
For that purpose, it offers and interface that will load the given script
onto the Redis server and on subsequent uses avoid doing so.

Do not use this module if it can happen that all scripts are flushed
from the Redis instance during the life time of a script cache object.

=head1 METHODS

=head2 new

Expects key/value pairs of options.
The only (and mandatory) option is C<redis_conn>, an instance of
the L<Redis> module to use to talk to the Redis server.

=head2 register_script

Given a Lua script to register as the first argument,
this makes sure that the script is available via its
SHA-1 on the Redis server.

Returns the script's SHA-1.

=head2 run_script

Given a script SHA-1 (hex) as first argument and an array
reference as second argument, executes the corresponding Lua
script on the Redis server and passes the contents of the array
reference as parameters to the C<$redis-E<gt>evalsha($sha, ...)>
call. Refer to L<http://redis.io/commands/evalsha> for details.

If the second parameter is omitted, it's assumed to be a script
call without parameters, so that

  $cache->run_script($sha);

is the same as:

  $cache->run_script($sha, [0]);

If the third parameter is a string, it is assumed to be the actual
script string. This can be used to transparently call C<register_script>
for you in case the cache hasn't seen this SHA1 before.

Returns the results of the C<evalsha> call.

=head1 SEE ALSO

L<Redis>

L<http://redis.io>

=head1 AUTHOR

Steffen Mueller, C<smueller@cpan.org>

=head1 COPYRIGHT AND LICENSE

 (C) 2012 Steffen Mueller. All rights reserved.
 
 This code is available under the same license as Perl version
 5.8.1 or higher.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut

