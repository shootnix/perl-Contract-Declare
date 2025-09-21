package App::Adaptor::Repo;

use Contract::Declare;
use Types::Standard qw/Int HashRef Maybe Str Bool/;


contract 'App::Adaptor::Repo' => interface {
    method get => (Int),     returns(Maybe[HashRef], Maybe[Str]);
    method set => (HashRef), returns(Maybe[Str]);
};

1;