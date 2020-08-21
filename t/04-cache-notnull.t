#!perl
use 5.20.0;
use strict;
use warnings FATAL => 'all';
BEGIN { $ENV{MAIL_BIMI_CACHE_BACKEND} = 'Null' };
use lib 't';
use Mail::BIMI::Prelude;
use Capture::Tiny qw{ capture };
use Test::More;
use Test::Exception;
use Mail::BIMI;
use Mail::BIMI::CacheBackend::File;
use Mail::BIMI::CacheBackend::FastMmap;
use Net::DNS::Resolver::Mock 1.20200214;

my $resolver = Net::DNS::Resolver::Mock->new;
$resolver->zonefile_read('t/zonefile');
my $bimi = Mail::BIMI->new(domain=>'gallifreyburning.com');
$bimi->resolver($resolver);

mkdir 't/tmp' if ! -e 't/tmp';
system('rm -rf t/tmp/cache') if -e 't/tmp/cache';
mkdir 't/tmp/cache';

subtest 'File Backend' => sub {
  cache_tests_for(
    {cache_backend=>'File',cache_file_directory=>'t/tmp/cache/'},
    sub{
      is(-e 't/tmp/cache/mail-bimi-cache-166cc1317749e82abc10e4068941f912fa774baf.cache',1,'Cache file 1 exists');
      is(-e 't/tmp/cache/mail-bimi-cache-a006e1d871a91903c028e60eaa358fbe117bd8d2.cache',1,'Cache file 2 exists');
      is(-e 't/tmp/cache/fastmmap',undef,'FastMmap file does not exist');
    },
  );
};

mkdir 't/tmp' if ! -e 't/tmp';
system('rm -rf t/tmp/cache') if -e 't/tmp/cache';
mkdir 't/tmp/cache';

subtest 'FastMmap Backend' => sub {
  cache_tests_for(
    {cache_backend=>'FastMmap',cache_fastmmap_share_file=>'t/tmp/cache/fastmmap'},
    sub{
      is(-e 't/tmp/cache/mail-bimi-cache-166cc1317749e82abc10e4068941f912fa774baf.cache',undef,'Cache file 1 does not exist');
      is(-e 't/tmp/cache/mail-bimi-cache-a006e1d871a91903c028e60eaa358fbe117bd8d2.cache',undef,'Cache file 2 does not exist');
      is(-e 't/tmp/cache/fastmmap',1,'FastMmap file exists');
    },
  );
};

sub cache_tests_for {
  my ($options,$middle) = @_;

  subtest 'Cache does not save without finish' => sub{
    {
      my $bimi = Mail::BIMI->new(domain=>'gallifreyburning.com',time=>1000,options=>$options);
      $bimi->resolver($resolver);
      $bimi->record->is_valid; # Make the Fetch Happen
      my $backend = Mail::BIMI::CacheBackend::Null->new(parent=>$bimi->record);
      is($bimi->record->version,'bimi1','Version is ok');
      $bimi->record->version('foo');
      is($bimi->record->version,'foo','Version is set ok');
    };
    {
      my $bimi = Mail::BIMI->new(domain=>'gallifreyburning.com',time=>1010,options=>$options);
      $bimi->resolver($resolver);
      $bimi->record->is_valid; # Make the Fetch Happen
      my $backend = Mail::BIMI::CacheBackend::Null->new(parent=>$bimi->record);
      is($bimi->record->version,'bimi1','Version is still ok');
    };
  };

  subtest 'Cache saved when finish called' => sub{
    {
      my $bimi = Mail::BIMI->new(domain=>'gallifreyburning.com',time=>1000,options=>$options);
      $bimi->resolver($resolver);
      $bimi->record->is_valid; # Make the Fetch Happen
      my $backend = Mail::BIMI::CacheBackend::Null->new(parent=>$bimi->record);
      is($bimi->record->version,'bimi1','Version is ok');
      $bimi->record->version('foo');
      is($bimi->record->version,'foo','Version is set ok');
      $bimi->finish;
    };
    {
      my $bimi = Mail::BIMI->new(domain=>'gallifreyburning.com',time=>1010,options=>$options);
      $bimi->resolver($resolver);
      $bimi->record->is_valid; # Make the Fetch Happen
      my $backend = Mail::BIMI::CacheBackend::Null->new(parent=>$bimi->record);
      is($bimi->record->version,'foo','Version is from cache');
    };
    &$middle;
    {
      my $bimi = Mail::BIMI->new(domain=>'gallifreyburning.com',time=>4610,options=>$options);
      $bimi->resolver($resolver);
      $bimi->record->is_valid; # Make the Fetch Happen
      my $backend = Mail::BIMI::CacheBackend::Null->new(parent=>$bimi->record);
      is($bimi->record->version,'bimi1','Cache expires');
    };
  };
}

done_testing;



