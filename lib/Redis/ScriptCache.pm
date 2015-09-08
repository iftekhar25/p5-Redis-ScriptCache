package Redis::ScriptCache;
use strict;
use warnings;

our $VERSION = '0.01';

use Digest::SHA1 qw(sha1_hex);
use File::Basename;
use File::Spec;
use Carp;

use Class::XSAccessor {
    getters => [qw(
        redis_conn
        script_dir
        _script_cache
    )],
};

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;

    # initialize the cache
    $self->{_script_cache} = {};
    # redis_conn is compulsory
    $self->redis_conn
        or croak("Need Redis connection");
    # canonicalize script_dir
    $self->_set_script_dir;

    return $self;
}

sub _set_script_dir {
    my( $self, $script_dir ) = @_;
    my $script_dir_to_set = $script_dir // $self->script_dir // undef;
    $self->{script_dir} = File::Spec->catdir( File::Spec->splitdir( $script_dir_to_set ) )
        if $script_dir_to_set;
    return $self;
}

sub register_all_scripts {
    my $self = shift;
    my %args = @_;

    $self->_set_script_dir( $args{script_dir} )
        if $args{script_dir};

    if ( $self->script_dir ) {
        for my $file (glob($self->script_dir . "/*.lua")) {
            $self->register_file(basename($file));
        }
        return $self->scripts;
    } else {
        croak("No script_dir specified");
    }
}

sub register_script {
    my ($self, $script_name, $script) = @_;
    my $script_ref = ref($script) ? $script : \$script;
    return $script_name
        if exists $self->{_script_cache}->{$script_name};

    my $sha = $self->redis_conn->script_load($$script_ref);
    $self->{_script_cache}->{$script_name} = $sha;

    return $script_name;
}

sub run_script {
    my ($self, $script_name, $args) = @_;
    
    my $conn = $self->redis_conn;
    my $sha = $self->_script_cache->{$script_name};

    if ( !$sha ) {
        croak("Unknown script $script_name");
    }

    return $conn->evalsha($sha, ($args ? (@$args) : (0)));
}

sub register_file {
    my ($self, $path_to_file) = @_;
    open my $fh, '<', File::Spec->catdir( $self->script_dir, $path_to_file )
        or croak "error opening $path_to_file: $!";

    my $script_name = basename( $path_to_file );
    $script_name =~ s/\.lua$//;
    my $script = do { local $/; <$fh> };
    return $self->register_script($script_name, $script);
}

sub call {
    my $self = shift;
    my $script_name = shift;

    return $self->run_script( $self->_script_cache->{$script_name}, \@_ )
        if $self->_script_cache->{$script_name};

    croak("Unknown script $script_name");
}

sub scripts {
    my ($self) = @_;
    # return keys in the _script_cache that aren't sha1 => 1,
    # but script_name => sha1
    return grep { $self->_script_cache->{$_} ne '1' } keys %{ $self->_script_cache };
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

