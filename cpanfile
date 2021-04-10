requires "AnyEvent" => "7.09";
requires "Async::Interrupt" => "1.21";
requires "EV" => "4.18";
requires "Exporter::Tiny" => "0.042";
requires "File::DataClass" => "v0.66.0";
requires "Future" => "0.32";
requires "List::Util" => "1.42";
requires "MIME::Base64" => "3.13";
requires "Moo" => "2.000001";
requires "Ref::Util" => "0.203";
requires "Try::Tiny" => "0.22";
requires "Type::Tiny" => "1.000005";
requires "Unexpected" => "v0.40.0";
requires "namespace::autoclean" => "0.26";
requires "perl" => "5.010001";
requires "strictures" => "2.000000";

on 'build' => sub {
  requires "Module::Build" => "0.4004";
  requires "version" => "0.88";
};

on 'test' => sub {
  requires "Class::Usul" => "0.84";
  requires "File::Spec" => "0";
  requires "Module::Build" => "0.4004";
  requires "Module::Metadata" => "0";
  requires "Sys::Hostname" => "0";
  requires "Test::Compile" => "v1.2.1";
  requires "Test::Requires" => "0.06";
  requires "version" => "0.88";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "2.120900";
};

on 'configure' => sub {
  requires "Module::Build" => "0.4004";
  requires "version" => "0.88";
};
