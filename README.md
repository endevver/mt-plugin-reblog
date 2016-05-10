#Reblog

Reblog is a Movable Type plugin that parses Atom and RSS feeds and transforms
feed entries into Movable Type entries. Imports can be run either manually or
in the background using
[run-periodic-tasks](http://www.movabletype.org/documentation/administrator/setting-up-run-periodic-taskspl.html).

# Dependencies

Reblog supports the following versions of Movable Type:

* Movable Type 4.25+
* Movable Type 5.1+
* Movable Type 6+

## Additional Perl Module Requirements

In addition to the
[System Requirements](http://www.movabletype.org/documentation/system-requirements.html)
for Movable Type, Reblog requires the following Perl modules:

* [DateTime](http://search.cpan.org/~drolsky/DateTime-0.78/lib/DateTime.pm)
* [Date::Parse](http://search.cpan.org/~gbarr/TimeDate-1.20/lib/Date/Parse.pm)

## Optional Perl Modules

To improve the performance of Reblog, the following modules may also be
installed.

* [XML::Liberal](http://search.cpan.org/~miyagawa/XML-Liberal-0.22/lib/XML/Liberal.pm)
* [XML::LibXML](http://search.cpan.org/~shlomif/XML-LibXML-2.0012/LibXML.pod)

Movable Type developers may also wish to install:

* Six Apart's [MT::Test](https://github.com/movabletype/movable-type-test) for
  running unit tests.

# Installation

Install the Perl modules discussed above using installation procedures for
[CPAN](http://www.cpan.org),
[CPANminus](https://raw.github.com/miyagawa/cpanminus/master/cpanm),
[PPM](http://code.activestate.com/ppm/), or the packaging system that is
supported by your operating system.

After downloading and uncompressing this package:

1. Upload the entire Reblog directory within the plugins directory of this
   distribution to the corresponding plugins directory within the Movable Type
   installation directory.
  * UNIX example:
    * Copy mt-plugin-reblog/plugins/reblog/ into /var/wwww/cgi-bin/mt/plugins/.
  * Windows example:
    * Copy mt-plugin-reblog/plugins/reblog/ into C:\webroot\mt-cgi\plugins\ .

# Configuration

Once installed, this plugin appears under the Tools menu in each blog in two
places:

* Tools > Reblog Configuration
* Tools > Reblog Sourcefeeds

# Additional Documentation

Additional documentation is located at
[https://github.com/movabletype/mt-plugin-reblog/wiki](https://github.com/movabletype/mt-plugin-reblog/wiki).

# License

This plugin is [MIT](http://opensource.org/licenses/MIT) licensed. See
LICENSE.md for the exact license.

# Authorship

This plugin has been contributed to by many current and former employees of Six
Apart, Ltd., After6 Services, 601am, Endevver, and YesItCan.be. See the
[Credits page](https://github.com/movabletype/mt-plugin-reblog/wiki/License,-Copyright,-and-Credits)
on the Reblog wiki for a list of specific individuals who have contributed.

The Reblog concept was initially developed at
[Reblog.org](http://www.reblog.org/) by the
[Eyebeam Art and Technology Center](http://www.eyebeam.org/),
[Stamen Design](http://stamen.com/), and other contributors.

# Copyright

Copyright © 2007 - 2013, Six Apart Ltd.  All Rights Reserved.

Enhancements to update frequencies and hierarchical category support,
additional documentation, Copyright © 2011-2013, After6 Services LLC. All
Rights Reserved.

Additional documentation contained in the Wiki, Copyright © 2011-2012, 601am
LLC. All Rights Reserved.
