requires "AnyEvent" => "7.07";
requires "Async::Interrupt" => "1.2";
requires "Class::Usul" => "v0.51.0";
requires "EV" => "4.18";
requires "Exporter::Tiny" => "0.042";
requires "Future" => "0.32";
requires "Moo" => "1.006000";
requires "Try::Tiny" => "0.22";
requires "namespace::autoclean" => "0.20";
requires "perl" => "5.010001";
requires "strictures" => "1.005005";

on 'build' => sub {
  requires "Module::Build" => "0.4004";
  requires "Test::Compile" => "v1.2.1";
  requires "Test::Requires" => "0.06";
  requires "version" => "0.88";
};

on 'configure' => sub {
  requires "Module::Build" => "0.4004";
  requires "version" => "0.88";
};
