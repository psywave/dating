
DESCRIPTION
-----------

    Dating - open source social profile database specially designed for
    gender-related experimentation in data analysis,

    and robot for downloading data from existing dating services (currently
    Russian Mamba only).

DATING DATABASE
---------------

    For deploying dating database use Dating::She. See
    examples/20-create-and-read-profiles.pl for trivial usage example and
    perldoc lib/Dating/She.pm for details. Dating::She describes generic
    attributes of dating profile and methods:

    *  load user profile from sql

    *  save or merge profile to sql

    *  parse html pages of 3rd party (Mamba) dating profile, and other

Dating database features
------------------------

    *  Proposed data model is well documented (see perldoc
       lib/Dating/She.pm). Attributes and methods can directly provide data
       for your discrete data analysis, see distintions_ methods in
       Dating::She.

    *  Uses MySQL for storage, data is serialized/deserialized
       automatically.

    *  New versions of Dating will be backward compatible with previous,
       database may be updated automatically, see
       examples/10-update-sql-schema.pl.

    *  Recognizes plagiarism by means of web search, and handles it
       differently, see 'manual' and 'copypaste' attributes of Dating::She.

CLIENT ROBOT
------------

    For searching and downloading profiles from 3rd party web service use
    Dating::Me. See examples/30-fetch-from-dating-service.pl for example
    usage and perldoc Dating/Me.pm for details. Dating::Me inherits
    LWP::UserAgent and is able to:

    *  search for profiles on dating site (Mamba)

    *  load profiles from site and store them in database

Client robot features
---------------------

    *  Different Me objects can share and update the same set of She objects
       cooperatively, overcoming dating service restrictions for single
       account.

    *  User location may be calculated from distances shown to different
       users by the procedure known as trilateration (see "guessing user
       location" in doc/INSTALL).

    *  Login to 3rd party dating site is performed automatically and only
       when necessary. Captcha is recognized and may be resolved manually or
       automatically via callback function (example may be provided on
       request).

    *  Changes in 3rd party html and json structure are easily detected, see
       fc_ok/fc_fail functions. Should some parser feature fail repeatedly,
       just update the modules from git.

    *  Javascript interpreter may be added readily when necessary.

LICENSE
-------

    Copyright 2012-2014, Anatoly Schrödinger <weirdo2@opmbx.org>

    This program is free software; you can redistribute it and/or modify it
    under the same terms as Perl itself. See
    <http://dev.perl.org/licenses/artistic.html>

SEE ALSO
--------

    Repository: <https://github.com/psywave/dating>
    Deployment example: <http://date33.org>

