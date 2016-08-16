#############################################################################
# Copyright © 2007-2009 Six Apart Ltd.
# Copyright © 2011, After6 Services LLC.
# This program is free software: you can redistribute it and/or modify it 
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation, or (at your option) any later version.  
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or 
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License 
# version 2 for more details.  You should have received a copy of the GNU 
# General Public License version 2 along with this program. If not, see 
# <http://www.gnu.org/licenses/>.
# $Id: Import.pm 17902 2009-04-07 02:16:15Z steve $

package Reblog::Worker::Import;

use strict;
use base qw( TheSchwartz::Worker );

use TheSchwartz::Job;
use MT;
use MT::Author;
use MT::Blog;
use MT::Plugin;
use Reblog::Util;
use Reblog::ReblogSourcefeed;

sub work {
    my $class = shift;
    my TheSchwartz::Job $job = shift;

    # Build this
    my $mt = MT->instance;

    my @jobs;
    push @jobs, $job;
    if ( my $key = $job->coalesce ) {
        while (
            my $job
            = MT::TheSchwartz->instance->find_job_with_coalescing_value(
                $class, $key
            )
            )
        {
            push @jobs, $job;
        }
    }

    foreach $job (@jobs) {
        my $hash          = $job->arg;
        my $sourcefeed_id = $job->uniqkey;
        my $msg;

        $sourcefeed_id =~ s/^reblog_//;
        my $sourcefeed = Reblog::ReblogSourcefeed->load({ id => $sourcefeed_id});
        if (!$sourcefeed) {
            $msg = "Reblog could not find a sourcefeed with the ID "
                . "$sourcefeed_id.";
            $mt->log({
                level    => $mt->model('log')->ERROR(),
                class    => 'reblog',
                category => 'import',
                message  => $msg,
            });
            $job->failed('Error with Reblog job ' . $job->id . ': ' . $msg);
            next;
        }

        MT::TheSchwartz->debug(
            "Importing sourcefeed $sourcefeed_id (" . $sourcefeed->url . ")..."
        );

        my $blog_id = $sourcefeed->blog_id;
        my $blog    = $mt->model('blog')->load({ id => $blog_id });
        if (!$blog) {
            $msg = "Reblog could not find a blog with the ID $blog_id for "
                . "sourcefeed ID $sourcefeed_id.";
            $mt->log({
                level    => $mt->model('log')->ERROR(),
                class    => 'reblog',
                category => 'import',
                blog_id  => $blog_id,
                message  => $msg,
            });
            $job->failed('Error with Reblog job ' . $job->id . ': ' . $msg);
            next;
        }

        my $plugin    = MT->component('reblog');
        my $author_id = $plugin->get_config_value(
            'default_author',
            'blog:' . $blog_id
        );
        my $author = MT::Author->load({ id => $author_id });
        if (!$author) {
            $mt->log({
                level    => $mt->model('log')->ERROR(),
                class    => 'reblog',
                category => 'import',
                blog_id  => $blog_id,
                message  => "Reblog could not find the specified default "
                    . "author, ID $author_id.",
            });
            $author ||= -1;
        }

        if ( $sourcefeed && $blog && $author ) {
            &Reblog::Util::do_import( '', $author, $blog, $sourcefeed );
            $job->completed();
            if ( $sourcefeed->is_active ) {
                $sourcefeed->inject_worker();
            }
        }
        else {
            my $url = $sourcefeed->url;
            $job->failed(
                "Error with Reblog job " . $job->id . " for url " . $url
            );
        }
    }
}

sub grab_for    {60}
sub max_retries {20}

sub retry_delay {
    my $self = shift;
    my ($failures) = @_;
    unless ( $failures && ( $failures + 0 ) ) {    # Non-zero digit
        return 600;
    }
    return 600  if $failures < 10;
    return 1800 if $failures < 15;
    return 60 * 60 * 12;
}

1;

