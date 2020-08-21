package Mail::BIMI::Role::Cacheable;
# ABSTRACT: Cache handling
# VERSION
use 5.20.0;
use Moose::Role;
use Mail::BIMI::Prelude;
use Mail::BIMI::Trait::Cacheable;
use Mail::BIMI::Trait::CacheKey;
use Mail::BIMI::CacheBackend::FastMmap;
use Mail::BIMI::CacheBackend::File;
use Mail::BIMI::CacheBackend::Null;

has _do_not_cache => ( is => 'rw', isa => Int, required => 0 );
has _cache_read_timestamp => ( is => 'rw', required => 0 );
has _cache_key => ( is => 'rw' );
has _cache_fields => ( is => 'rw' );
has cache_backend => ( is => 'ro', lazy => 1, builder => '_build_cache_backend' );
requires 'cache_valid_for';

=head1 DESCRIPTION

Role allowing the cacheing of data in a class based on defined cache keys

=cut

=method I<do_not_cache()>

Do not cache this object

=cut

sub do_not_cache($self) {
  $self->_do_not_cache(1);
}

sub _build_cache_backend($self) {
  my %opts = (
    bimi_object => $self->bimi_object,
    parent => $self,
  );
  my $backend_type = $self->bimi_object->options->cache_backend;
  my $backend
              = $backend_type eq 'FastMmap' ? Mail::BIMI::CacheBackend::FastMmap->new( %opts )
              : $backend_type eq 'File' ? Mail::BIMI::CacheBackend::File->new( %opts )
              : $backend_type eq 'Null' ? Mail::BIMI::CacheBackend::Null->new( %opts )
              : croak 'Unknown Cache Backend';
  $self->verbose('Using cache backend '.$backend_type);
  return $backend;
}

around new => sub{
  my $original = shift;
  my $class = shift;
  my $self = $class->$original(@_);
  my @cache_key;
  my @cache_fields;

  my $meta = $self->meta;
  foreach my $attribute_name ( sort $meta->get_attribute_list ) {
    my $attribute = $meta->get_attribute($attribute_name);
    if ( $attribute->does('Mail::BIMI::Trait::CacheKey') && $attribute->does('Mail::BIMI::Trait::Cacheable') ) {
      croak "Attribute $attribute_name cannot be BOTH is_cacheable AND is_cache_key";
    }
    elsif ( $attribute->does('Mail::BIMI::Trait::CacheKey') ) {
      push @cache_key, "$attribute_name=".($self->{$attribute_name}//'');
    }
    elsif ( $attribute->does('Mail::BIMI::Trait::Cacheable') ) {
      push @cache_fields, $attribute_name;
    }
  }

  croak "No cache key defined" if ! @cache_key;
  croak "No cacheable fields defined" if ! @cache_fields;

  $self->_cache_key( join("\n",
    ref $self,
    @cache_key,
  ));
  $self->_cache_fields( \@cache_fields );

  my $data = $self->cache_backend->get_from_cache;
  return $self if !$data;
  $self->verbose('Build '.(ref $self).' from cache');
  if ($data->{cache_key} ne $self->_cache_key){
    warn 'Cache is invalid';
    return $self;
  }
  if ($data->{timestamp}+$self->cache_valid_for < $self->bimi_object->time) {
    $self->cache_backend->delete_cache;
    return $self;
  }

  $self->_cache_read_timestamp($data->{timestamp});
  foreach my $cache_field ( $self->_cache_fields->@* ) {
    if ( exists ( $data->{data}->{$cache_field} )) {
      my $value = $data->{data}->{$cache_field};
      my $attribute = $meta->get_attribute($cache_field);
      if ( $attribute->does('Mail::BIMI::Trait::CacheSerial') ) {
        my $method_name = 'deserialize_'.$cache_field;
        $self->$method_name($value);
      }
      else {
        $self->{$cache_field} = $value;
      }
    }
  }

  return $self;
};

sub _write_cache($self) {
  return if $self->_do_not_cache;
  $self->_do_not_cache(1);
  my $meta = $self->meta;
  my $time = $self->bimi_object->time;
  my $data = {
    cache_key => $self->_cache_key,
    timestamp => $self->_cache_read_timestamp // $time,
    data => {},
  };
  foreach my $cache_field ( $self->_cache_fields->@* ) {
    if ( defined ( $self->{$cache_field} )) {

      my $value = $self->{$cache_field};
      my $attribute = $meta->get_attribute($cache_field);
      if ( $attribute->does('Mail::BIMI::Trait::CacheSerial') ) {
        my $method_name = 'serialize_'.$cache_field;
        $value = $self->$method_name;
      }

      $data->{data}->{$cache_field} = $value;
    }
  }

  $self->cache_backend->put_to_cache($data);
}

1;
