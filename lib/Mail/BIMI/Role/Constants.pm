package Mail::BIMI::Role::Constants;
# ABSTRACT: Class to model defined constants
# VERSION
use 5.20.0;
use Moo::Role;
use Types::Standard qw{Str HashRef ArrayRef};
use Type::Utils qw{class_type};
use Mail::BIMI::Pragmas;

sub NO_BIMI_RECORD { return 'no BIMI records found' };
sub MULTI_BIMI_RECORD { return 'multiple BIMI records found' };

1;
