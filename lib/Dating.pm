package Dating;

################
#
# Dating - social profile database
#
# Anatoly Schrödinger
# weirdo2@opmbx.org
#
# Dating.pm is mostly for README
#
################

use warnings;
use strict;
use utf8;

our $VERSION = "1.02";
use Dating::Me;
use Dating::She;

=encoding UTF-8

=head1 NAME

Dating - social profile database

=head1 SYNOPSIS

  use Dating;

  # first initialize database, see INSTALL

  my $she = Dating::She->new();
  $she->{nick} = "Test User 1";
  $she->copy_to_db ($dbh);

  my $me = Dating::Me->new (service=>mamba, login=>$login, password=>$password);
  for ($me->search (mysex=>'M', sex=>'F', agelow=>25, agehigh=>30)) {
	$she = Dating::She->new_from_url ($_, $me);
	$she->sync_with_db ($dbh);
  }

  # see examples

=head1 DESCRIPTION

Dating - open source social profile database specially designed for gender-related 
experimentation in data analysis,

and robot for downloading data from existing dating services (currently Russian Mamba only).

=head1 DATING DATABASE

For deploying dating database use Dating::She.
See examples/20-create-and-read-profiles.pl for trivial usage example.
Dating::She describes generic attributes of dating profile 
and methods:

=over 3

=item *

load user profile from sql

=item *

save or merge profile to sql

=item *

parse html pages of 3rd party (Mamba) dating profile, and other

=back

=head1 Dating database features

=over 3

=item *

Proposed data model is well documented (see Dating::She). 
Attributes and methods can directly provide data for your discrete 
data analysis, see distintions_ methods in Dating::She.

=item *

Uses MySQL for storage, data is serialized/deserialized automatically.

=item *

New versions of Dating will be backward compatible with previous, 
database may be updated automatically, see examples/10-update-sql-schema.pl.

=item *

Recognizes plagiarism by means of web search, 
and handles it differently, see 'manual' and 'copypaste' attributes 
of Dating::She.

=back



=head1 CLIENT ROBOT

For searching and downloading profiles from 3rd party web service
use Dating::Me.
See examples/30-fetch-from-dating-service.pl for example usage.
Dating::Me inherits LWP::UserAgent and is able to:


=over 3

=item *

search for profiles on dating site (Mamba)

=item *

load profiles from site and store them in database

=back



=head1 Client robot features

=over 3

=item *

Different Me objects can share and update the same set of She objects
cooperatively, overcoming dating service restrictions for single account.

=item *

User location may be calculated from distances shown to different users
by the procedure known as trilateration (see "guessing user location" 
in INSTALL).

=item *

Login to 3rd party dating site is performed automatically and only 
when necessary. Captcha is recognized and may be resolved manually 
or automatically via callback function (example may be provided on request).

=item *

Changes in 3rd party html structure are easily detected, see fc_ok/fc_fail functions. 
Should some parser feature fail repeatedly, just update the modules 
from git.

=item *

Javascript interpreter may be added readily when necessary.

=back

=head1 LICENSE

Copyright 2012-2014, Anatoly Schrödinger <weirdo2@opmbx.org>

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
See L<http://dev.perl.org/licenses/artistic.html>

=head1 SEE ALSO

L<Dating::She>, L<Dating::Me>

Repository: L<https://github.com/psywave/dating>

=cut
-1

