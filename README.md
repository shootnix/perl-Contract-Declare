# Contract::Declare

[![CI](https://github.com/shootnix/perl-Contract-Declare/actions/workflows/ci.yml/badge.svg)](https://github.com/shootnix/perl-Contract-Declare/actions)
[![CPAN Version](https://badge.fury.io/pl/perl-Contract-Declare.svg)](https://metacpan.org/pod/Contract::Declare)
[![License](https://img.shields.io/badge/license-Perl%20Artistic-blue.svg)](https://dev.perl.org/licenses/artistic.html)
[![Issues](https://img.shields.io/github/issues/shootnix/perl-Contract-Declare.svg)](https://github.com/shootnix/perl-Contract-Declare/issues)
[![Stars](https://img.shields.io/github/stars/shootnix/perl-Contract-Declare.svg)](https://github.com/shootnix/perl-Contract-Declare/stargazers)

---

**Contract::Declare** is a small design-by-contract toolkit for Perl. It lets you declare an
**interface** — a named set of method signatures — separately from any class that implements it,
and enforces those signatures at runtime: every call to an implementing method has its arguments
and its return value checked against the declared types before the caller ever sees the result.

---

## Features

- Declare interfaces as plain packages, with method signatures expressed via
  `:Expects(...)` / `:Returns(...)` attributes
- Every implementing method is wrapped with a runtime type check on the way in and out
- Types are resolved through `Type::Parser` / `Type::Registry`, so any `Types::Standard`
  type name works out of the box (`Str`, `Int`, `Num`, `Bool`, `Object`, `HashRef`,
  `ArrayRef`, `Maybe[Str]`, `Any`, ...)
- Missing methods are caught early, with a clear error naming the class, the interface,
  and the missing sub
- No inheritance imposed on implementing classes — just a `use` statement

---

## Installation

Install via CPAN:

```bash
cpanm Contract::Declare
```

Or manually:

```bash
perl Makefile.PL
make
make test
make install
```

---

## Synopsis

```perl
# 1. Declare an interface: a package name plus a set of subs whose
#    parameter and return types are the contract.
package My::Reader {
    use Contract::Declare::Interface name => 'Reader';

    sub read :Expects(Object, Str) :Returns(Str);
}

# 2. Implement it. Every sub required by the interface must exist;
#    Contract::Declare wraps each one with a runtime type check.
package My::JSONReader {
    use My::Reader;
    use Contract::Declare::Implements qw/Reader/;

    sub new { return bless {}, shift }

    sub read {
        my ($self, $filename) = @_;
        ...
        return $file_contents;
    }
}

# 3. Use it. Arguments and return values are validated on every call.
my $reader = My::JSONReader->new;
my $text   = $reader->read('data.json');   # ok
$reader->read('data.json', 'oops');        # dies: wrong number of parameters
$reader->read([]);                         # dies: types mismatch: Str
```

---

## How it works

The distribution is split into two collaborating modules:

- **[Contract::Declare::Interface](lib/Contract/Declare/Interface.pm)** — declares an interface:
  a name, and a set of subs annotated with `:Expects(...)` and `:Returns(...)` attributes
  describing the types of their parameters (including the invocant) and their return value.
- **[Contract::Declare::Implements](lib/Contract/Declare/Implements.pm)** — marks a class as
  implementing one or more interfaces. Every sub required by those interfaces must already
  exist in the class; Contract::Declare replaces each one with a wrapper that validates
  arguments on the way in and the return value on the way out, using `Types::Standard`
  type names.

Interfaces are recorded in a process-wide registry keyed by interface name. When a class does

```perl
use Contract::Declare::Implements qw/SomeInterface/;
```

it registers itself as an implementor of `SomeInterface`. At the end of compilation (Perl's
`INIT` phase, i.e. once every `use` in the program has run), `Contract::Declare::Implements`
walks every registered implementor and, for each sub required by its interface(s):

1. confirms the class actually defines that sub (via `$class->can(...)`);
2. replaces it with a wrapper that validates `@_` against `:Expects`, calls the original
   implementation, validates the result against `:Returns`, and then returns it to the caller.

---

## Caveats

- **Implementing classes must be compiled before `INIT` time.** Contract enforcement is wired
  up in an `INIT` block, which only fires once, after the whole program has finished compiling.
  A class loaded via a top-level `use` (directly or indirectly) gets wrapped correctly. A class
  loaded later at runtime via `require` (lazy-loading, plugin systems, etc.) is silently **not**
  wrapped: its methods run unmodified, with no argument or return-value checking at all, and no
  warning is issued.
- **`:Expects`/`:Returns` are global attributes.** `Contract::Declare::Interface` installs its
  `:Expects` and `:Returns` attribute handlers into `UNIVERSAL`, which makes them visible to
  every package in the process once the module has been loaded once, not just to packages that
  declare an interface. Attaching either attribute to a sub in a package that never called
  `use Contract::Declare::Interface name => ...` raises a "panic: can't find any interface
  implemented in ..." error.
- **Interface names are unique per process.** Two interfaces cannot share a name; the second
  `use Contract::Declare::Interface name => 'Same'` dies immediately.
- **Only `Types::Standard` type names are recognised.** `:Expects`/`:Returns` are checked
  against a `Type::Registry` that only has `Types::Standard` loaded. Type libraries from your
  own application are not available unless you extend the registry yourself.
- **Contract violations always `croak`.** There is no soft-fail mode; wrap calls in
  `eval`/`Try::Tiny` if you need to recover from a contract violation instead of dying.

---

## See also

[Contract::Declare](lib/Contract/Declare.pm),
[Contract::Declare::Interface](lib/Contract/Declare/Interface.pm),
[Contract::Declare::Implements](lib/Contract/Declare/Implements.pm),
[Type::Tiny](https://metacpan.org/pod/Type::Tiny),
[Types::Standard](https://metacpan.org/pod/Types::Standard),
[Attribute::Handlers](https://metacpan.org/pod/Attribute::Handlers)

---

## Contributing

Bug reports and pull requests are welcome!

Please submit issues and feature requests via
[GitHub Issues](https://github.com/shootnix/perl-Contract-Declare/issues).

---

## License

This library is free software; you can redistribute it and/or modify it under the same terms
as Perl itself.

See the [Artistic License 1.0](https://dev.perl.org/licenses/artistic.html) for details.

---

## Author

**Alexander Ponomarev** (<shootnix@gmail.com>)

Project: [GitHub Repository](https://github.com/shootnix/perl-Contract-Declare)
