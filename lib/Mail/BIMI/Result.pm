package Mail::BIMI::Result;
# ABSTRACT: Class to model a BIMI result
# VERSION
use 5.20.0;
use Moo;
use Types::Standard qw{Str HashRef ArrayRef};
use Type::Utils qw{class_type};
use Mail::BIMI::Pragmas;
use Mail::AuthenticationResults::Header::Entry;
use Mail::AuthenticationResults::Header::SubEntry;
use Mail::AuthenticationResults::Header::Comment;
  has bimi_object => ( is => 'ro', isa => class_type('Mail::BIMI'), required => 1, weaken => 1);
  has result => ( is => 'rw', isa => Str );
  has comment => ( is => 'rw', isa => Str );
  has headers => ( is => 'rw', isa => HashRef );

sub domain($self) {
  return $self->bimi_object->domain;
}

sub selector($self) {
  return $self->bimi_object->selector;
}

sub set_result($self,$result,$comment) {
  $self->result($result);
  $self->comment($comment);
}

sub get_authentication_results_object($self) {
  my $header = Mail::AuthenticationResults::Header::Entry->new()->set_key( 'bimi' )->safe_set_value( $self->result );
  if ( $self->comment ) {
    $header->add_child( Mail::AuthenticationResults::Header::Comment->new()->safe_set_value( $self->comment ) );
  }
  if ( $self->result eq 'pass' ) {
    $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'header.d' )->safe_set_value( $self->bimi_object->record->domain ) );
    $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'header.selector' )->safe_set_value( $self->bimi_object->record->selector ) );
  }
  if ( $self->bimi_object->record->authority->is_relevant ) {
    my $vmc = $self->bimi_object->record->authority->vmc;
    $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'policy.authority' )->safe_set_value( $vmc->is_valid ? 'pass' : 'fail' ) );
    $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'policy.authority-uri' )->safe_set_value( $self->bimi_object->record->authority->authority ) );
    if ( $self->result eq 'pass' ) {
      $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'policy.authority-not-before' )->safe_set_value( $vmc->not_before ) );
      $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'policy.authority-not-after' )->safe_set_value( $vmc->not_after ) );
      $header->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( 'policy.authority-issuer' )->safe_set_value( $vmc->issuer ) );
    }
  }

  return $header;
}

sub get_authentication_results($self) {
  return $self->get_authentication_results_object->as_string;
}

1;
