package Mail::BIMI::Indicator;
# ABSTRACT: Class to model a BIMI indicator
# VERSION
use 5.20.0;
use Moose;
use Moose::Util::TypeConstraints;
use Mail::BIMI::Prelude;
use File::Slurp qw{ read_file write_file };
use IO::Uncompress::Gunzip;
use MIME::Base64;
use Term::ANSIColor qw{ :constants };
use XML::LibXML;
our @VALIDATOR_PROFILES = qw{ SVG_1.2_BIMI SVG_1.2_PS Tiny-1.2 };

extends 'Mail::BIMI::Base';
with(
  'Mail::BIMI::Role::HasError',
  'Mail::BIMI::Role::HasHTTPClient',
  'Mail::BIMI::Role::Data',
  'Mail::BIMI::Role::Cacheable',
);
has uri => ( is => 'rw', isa => 'Str', traits => ['CacheKey'],
  documentation => 'inputs: URL to retrieve Indicator from', );
has source => ( is => 'rw', isa => 'Str', traits => ['Cacheable'],
  documentation => 'Human readable summary of where this indicator was retrieved from' );
has data => ( is => 'rw', isa => 'Str', lazy => 1, builder => '_build_data', traits => ['Cacheable'],
  documentation => 'inputs: Raw data representing the Indicator; Fetches from uri if not given', );
has data_uncompressed => ( is => 'rw', isa => 'Str', lazy => 1, builder => '_build_data_uncompressed', traits => ['Cacheable'],
  documentation => 'Raw data in uncompressed form' );
has data_xml => ( is => 'rw', lazy => 1, builder => '_build_data_xml',
  documentation => 'XML::LibXML object representing the Indicator' );
has is_valid => ( is => 'rw', lazy => 1, builder => '_build_is_valid', traits => ['Cacheable'],
  documentation => 'Is this indicator valid' );
has parser => ( is => 'rw', lazy => 1, builder => '_build_parser',
  documentation => 'XML::LibXML::RelaxNG parser object used to validate the Indicator XML' );
has header => ( is => 'rw', lazy => 1, builder => '_build_header', traits => ['Cacheable'],
  documentation => 'Indicator data encoded as Base64 ready for insertion as BIMI-Indicator header' );
has validator_profile => ( is => 'rw', isa => enum(\@VALIDATOR_PROFILES), lazy => 1, builder => '_build_validator_profile', traits => ['Cacheable'],
  documentation => 'inputs: Validator profile used to validate the Indicator', );

=head1 DESCRIPTION

Class for representing, retrieving, validating, and processing a BIMI Indicator

=cut

sub _build_validator_profile($self) {
  return $self->bimi_object->options->svg_profile;
}

=method I<cache_valid_for()>

How long should the cache for this class be valid

=cut

sub cache_valid_for($self) { return 3600 }

=method I<http_client_max_fetch_size()>

Maximum permitted HTTP fetch

=cut

sub http_client_max_fetch_size($self) { return $self->bimi_object->options->svg_max_fetch_size };

sub _build_data_uncompressed($self) {
  my $data = $self->data;
  if ( $data =~ /^\037\213/ ) {
    $self->log_verbose('Uncompressing SVG');

    my $unzipped;
    IO::Uncompress::Gunzip::gunzip(\$data,\$unzipped);
    if ( !$unzipped ) {
      $self->add_error('SVG_UNZIP_ERROR');
      return '';
    }
    return $unzipped;
  }
  else {
    return $data;
  }
}

=method I<data_maybe_compressed()>

Synonym for data; returns the data in a maybe compressed format

=cut

sub data_maybe_compressed($self) {
  # Alias for clarity, the data is as received.
  return $self->data;
}

=method I<data_uncompressed_normalized()>

Returns the uncompressed data with normalized line endings

=cut

sub data_uncompressed_normalized($self) {
  my $data = $self->data_uncompressed;
  $data =~ s/\r\n?/\n/g;
  return $data;
}

sub _build_data_xml($self) {
  my $xml;
  my $data = $self->data_uncompressed;
  if ( !$data ) {
    $self->add_error('SVG_GET_ERROR');
    return;
  }
  eval {
    $xml = XML::LibXML->new->load_xml(string => $self->data_uncompressed);
    1;
  } || do {
    $self->add_error('SVG_INVALID_XML');
    $self->log_verbose("Invalid XML :\n".$self->data_uncompressed);
    return;
  };
  return $xml;
}

sub _build_parser($self) {
  state $parser = XML::LibXML::RelaxNG->new( string => $self->get_data_from_file($self->validator_profile.'.rng'));
  return $parser;
}

sub _build_data($self) {
  if ( ! $self->uri ) {
    $self->add_error('CODE_MISSING_LOCATION');
    return '';
  }
  if ($self->bimi_object->options->svg_from_file) {
    $self->log_verbose('Reading SVG from file '.$self->bimi_object->options->svg_from_file);
    return scalar read_file $self->bimi_object->options->svg_from_file;
  }
  $self->log_verbose('HTTP Fetch: '.$self->uri);
  my $response = $self->http_client->get( $self->uri );
  if ( !$response->{success} ) {
    if ( $response->{status} == 599 ) {
      $self->add_error('SVG_FETCH_ERROR',$response->{content});
    }
    else {
      $self->add_error('SVG_FETCH_ERROR',$response->{status});
    }
    return '';
  }
  return $response->{content};
}

sub _build_is_valid($self) {

  if (!($self->data||$self->uri)) {
    $self->add_error('CODE_NOTHING_TO_VALIDATE');
    return 0;
  }

  if (!$self->data) {
    $self->add_error('CODE_NO_DATA');
    return 0;
  }

  my $is_valid;
  if ( length $self->data_uncompressed > $self->bimi_object->options->svg_max_size ) {
    $self->add_error('SVG_SIZE');
  }
  else {
    if ( $self->bimi_object->options->no_validate_svg ) {
      $is_valid=1;
      $self->log_verbose('Skipping SVG validation');
    }
    else {
      eval {
        $self->parser->validate( $self->data_xml );
        $is_valid=1;
        $self->log_verbose('SVG is valid');
        1;
      } || do {
        my $validation_error = $@;
        my $error_text = ref $validation_error eq 'XML::LibXML::Error' ? $validation_error->as_string : $validation_error;
        $self->add_error('SVG_VALIDATION_ERROR',$error_text);
      };
    }
  }

  return 0 if $self->errors->@*;
  return 1;
}

sub _build_header($self) {
  return if !$self->is_valid;
  my $base64 = encode_base64( $self->data_uncompressed );
  $base64 =~ s/\n//g;
  my @parts = unpack("(A70)*", $base64);
  return join("\n    ", @parts);
}

=method I<finish()>

Finish and clean up, write cache if enabled.

=cut

sub finish($self) {
  $self->_write_cache;
}

=method I<app_validate()>

Output human readable validation status of this object

=cut

sub app_validate($self) {
  say 'Indicator'.($self->source ? ' (From '.$self->source.')' : '' ).' Returned: '.($self->is_valid ? GREEN."\x{2713}" : BRIGHT_RED."\x{26A0}").RESET;
  say YELLOW.'  GZipped        '.WHITE.': '.CYAN.($self->data_uncompressed eq $self->data?'No':'Yes').RESET;
  say YELLOW.'  BIMI-Indicator '.WHITE.': '.CYAN.$self->header.RESET if $self->is_valid;
  say YELLOW.'  Profile Used   '.WHITE.': '.CYAN.$self->validator_profile.RESET;
  say YELLOW.'  Is Valid       '.WHITE.': '.($self->is_valid?GREEN.'Yes':BRIGHT_RED.'No').RESET;
  if ( ! $self->is_valid ) {
    say "Errors:";
    foreach my $error ( $self->errors->@* ) {
      my $error_code = $error->code;
      my $error_text = $error->description;
      my $error_detail = $error->detail // '';
      $error_detail =~ s/\n/\n    /g;
      say BRIGHT_RED."  $error_code ".WHITE.': '.CYAN.$error_text.($error_detail?"\n    ".$error_detail:'').RESET;
    }
  }
}

1;

