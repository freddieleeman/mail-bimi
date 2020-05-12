package Mail::BIMI::Record::Location;
# ABSTRACT: Class to model a BIMI location
# VERSION
use 5.20.0;
use Moo;
use Mail::BIMI::Pragmas;
use Mail::BIMI::Identifier;
  with 'Mail::BIMI::Role::Error';
  with 'Mail::BIMI::Role::Constants';
  has location => ( is => 'rw', isa => sub{ undef || Str }, required => 1 );
  has is_valid => ( is => 'rw', lazy => 1, builder => '_build_is_valid' );
  has _is_valid => ( is => 'rw', lazy => 1, builder => '_build__is_valid' );
  has identifier => ( is => 'rw', lazy => 1, builder => '_build_identifier' );

sub _build__is_valid($self) {
  # Check is_valid without checking identifier, because recursion!
  if ( !defined $self->location ) {
    $self->add_error( $self->MISSING_L_TAG );
  }
  elsif ( $self->location eq '' ) {
    $self->add_error( $self->EMPTY_L_TAG );
  }
  elsif ( ! ( $self->location =~ /^https:\/\// ) ) {
    $self->add_error( $self->INVALID_TRANSPORT_L );
  }
  else {
  }

  return 0 if $self->error->@*;
  return 1;
}

sub _build_is_valid($self) {
  return 0 if !$self->_is_valid;
  if ( !$self->identifier->is_valid ) {
    $self->add_error( $self->identifier->error );
  }

  return 0 if $self->error->@*;
  return 1;
}

sub _build_identifier($self) {
  return if ! $self->_is_valid;
  return Mail::BIMI::Identifier->new( location => $self->location );
}

1;
