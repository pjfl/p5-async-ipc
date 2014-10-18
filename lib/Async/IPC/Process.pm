package Async::IPC::Process;

use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader read_exactly recv_rv_error send_msg );
use Class::Usul::Constants qw( FALSE SPC TRUE );
use Class::Usul::Functions qw( is_coderef throw );
use Class::Usul::Types     qw( ArrayRef CodeRef FileHandle
                               NonEmptySimpleStr PositiveInt Undef );
use English                qw( -no_match_vars );
use Scalar::Util           qw( weaken );
use Storable               qw( thaw );
use Try::Tiny;

extends q(Async::IPC::Base);

# Public attributes
has 'code'      => is => 'ro', isa => CodeRef | ArrayRef | NonEmptySimpleStr,
   required     => TRUE;

has 'max_calls' => is => 'ro', isa => PositiveInt, default => 0;

has 'on_exit'   => is => 'ro', isa => CodeRef | Undef;

has 'on_return' => is => 'ro', isa => CodeRef | Undef;

has 'reader'    => is => 'ro', isa => FileHandle | Undef;

has 'writer'    => is => 'ro', isa => FileHandle | Undef;

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   my $call_pipe = delete $attr->{call_pipe};
   my $retn_pipe = delete $attr->{retn_pipe};

   $call_pipe and $attr->{writer} = $call_pipe->[ 1 ];
   $retn_pipe and $attr->{reader} = $retn_pipe->[ 0 ];
   return $attr;
};

sub BUILD {
   my $self = shift; my $pid = $self->pid; # Start child process

   $self->on_exit   and $self->loop->watch_child( $pid, $self->on_exit );
   $self->on_return and $self->set_return_callback( $self->on_return );
   return;
}

# Public methods
sub is_running {
   return CORE::kill 0, $_[ 0 ]->pid;
}

sub send {
   my $self = shift; return send_msg $self->writer, $self->log, 'SNDARG', @_;
}

sub set_return_callback {
   my ($self, $code) = @_; my $rdr = $self->reader or return;

   my $lead = log_leader 'error', 'EXECRV', my $pid = $self->pid;

   my $log  = $self->log; my $loop = $self->loop;

   $loop->watch_read_handle( $rdr, sub {
      my $red = read_exactly $rdr, my $buf_len, 4;

      recv_rv_error $log, $pid, $red
         and return $loop->unwatch_read_handle( $rdr );
      $red = read_exactly $rdr, my $buf, unpack 'I', $buf_len;
      recv_rv_error $log, $pid, $red
         and return $loop->unwatch_read_handle( $rdr );

      try   { $code->( @{ $buf ? thaw $buf : [] } ) }
      catch { $log->error( $lead.$_ ) };

      return;
   } );

   return;
}

sub stop {
   my $self = shift; $self->is_running or return;

   my $lead = log_leader 'debug', $self->log_key, $self->pid;

   $self->log->debug( "${lead}Stopping ".$self->description );
   CORE::kill 'TERM', $self->pid;
   return;
}

# Private methods
sub _build_pid {
   my $self = shift; weaken( $self );
   my $temp = $self->config->tempdir;
   my $args = { async => TRUE, ignore_zombies => FALSE };
   my $name = $self->config->pathname->basename.SPC.(lc $self->log_key);
   my $cmd  = (is_coderef $self->code)
            ? [ sub { $PROGRAM_NAME = $name; $self->code->( $self ) } ]
            : $self->code;

   $self->debug and $args->{err} = $temp->catfile( (lc $self->log_key).'.err' );

   return $self->run_cmd( $cmd, $args )->pid;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Process - One-line description of the modules purpose

=head1 Synopsis

   use Async::IPC::Process;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head1 Diagnostics

=head1 Dependencies

=over 3

=item L<Class::Usul>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module. Please report problems to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=Async-IPC.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 Author

Peter Flanigan, C<< <pjfl@cpan.org> >>

=head1 License and Copyright

Copyright (c) 2014 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
