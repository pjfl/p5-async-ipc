<div>
    <a href="https://travis-ci.org/pjfl/p5-async-ipc"><img src="https://travis-ci.org/pjfl/p5-async-ipc.svg?branch=master" alt="Travis CI Badge"></a>
</div>

# Name

Async::IPC - Asyncronous inter process communication

# Synopsis

    use Async::IPC;

    my $factory = Async::IPC->new( builder => Class::Usul->new );

    my $notifier = $factory->new_notifier
       (  code => sub { ... code to run in a child process ... },
          desc => 'description used by the logger',
          name => 'logger key used to identify a log entry',
          type => 'routine' );

# Description

A callback style API implemented on [AnyEvent](https://metacpan.org/pod/AnyEvent)

I couldn't make [IO::Async](https://metacpan.org/pod/IO::Async) work with [AnyEvent](https://metacpan.org/pod/AnyEvent) and [EV](https://metacpan.org/pod/EV) so this instead

This module implements a factory pattern. It creates instances of the
notifier classes

# Configuration and Environment

Defines the following attributes;

- `builder`

    A required instance of [Class::Usul](https://metacpan.org/pod/Class::Usul)

- `loop`

    An instance of [Async::IPC::Loop](https://metacpan.org/pod/Async::IPC::Loop). Created by the constructor

# Subroutines/Methods

## `new_notifier`

Returns an object reference for a newly instantiated instance of a notifier
class. The notifier types and their classes are;

- `channel`

    An instance of [Async::IPC::Channel](https://metacpan.org/pod/Async::IPC::Channel)

- `file`

    An instance of [Async::IPC::File](https://metacpan.org/pod/Async::IPC::File)

- `function`

    An instance of [Async::IPC::Function](https://metacpan.org/pod/Async::IPC::Function)

- `handle`

    An instance of [Async::IPC::Handle](https://metacpan.org/pod/Async::IPC::Handle)

- `periodical`

    An instance of [Async::IPC::Periodical](https://metacpan.org/pod/Async::IPC::Periodical)

- `process`

    An instance of [Async::IPC::Process](https://metacpan.org/pod/Async::IPC::Process)

- `routine`

    An instance of [Async::IPC::Routine](https://metacpan.org/pod/Async::IPC::Routine)

- `semaphore`

    An instance of [Async::IPC::Semaphore](https://metacpan.org/pod/Async::IPC::Semaphore)

- `stream`

    An instance of [Async::IPC::Stream](https://metacpan.org/pod/Async::IPC::Stream)

## `new_future`

Returns an instance of [Async::IPC::Future](https://metacpan.org/pod/Async::IPC::Future)

# Diagnostics

None

# Dependencies

- [Class::Usul](https://metacpan.org/pod/Class::Usul)
- [Moo](https://metacpan.org/pod/Moo)
- [POSIX](https://metacpan.org/pod/POSIX)

# Incompatibilities

This module revolves around forking processes. Unless it developed a thread
model it won't work on `mswin32`

# Bugs and Limitations

There are no known bugs in this module. Please report problems to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=Async-IPC.
Patches are welcome

# Acknowledgements

Larry Wall - For the Perl programming language

# Author

Peter Flanigan, `<pjfl@cpan.org>`

# License and Copyright

Copyright (c) 2016 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See [perlartistic](https://metacpan.org/pod/perlartistic)

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE
