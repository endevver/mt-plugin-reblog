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
# $Id: ReblogSourcefeed.pm 17902 2009-04-07 02:16:15Z steve $

package Reblog::ReblogSourcefeed;
use strict;

use MT::Object;
use constant DEFAULT_WORKER_PRIORITY => 3;
use constant SECONDS_PER_MINUTE      => 60;
use constant URL_SIZE                => 255;

@Reblog::ReblogSourcefeed::ISA = qw( MT::Object );
__PACKAGE__->install_properties(
    {
        column_defs => {
            'id'           => 'integer not null auto_increment',
            'blog_id'      => 'integer not null',
            'label'        => 'string(255)',
            'url'          => 'string(' . URL_SIZE . ') not null',
            'is_active'    => 'boolean not null',
            'is_excerpted' => 'boolean not null',
            'build_assets' => 'boolean not null',
            'category_id'  => 'integer',
            'last_read'    => 'integer',
            # Does this column actually do anything? It's only used in the
            # inject_worker function below.
            'last_fired'   => 'integer',
            'total_fails'  => 'integer',
            'consec_fails' => 'integer',
            'has_error'    => 'boolean not null',
        },
        indexes => {
            blog_id => 1,
            url     => 1,
        },
        audit       => 1,
        datasource  => 'reblog_srcfeed',
        primary_key => 'id',
    }
);

sub class_label {
    MT->translate("Sourcefeed");
}

sub class_label_plural {
    MT->translate("Sourcefeeds");
}

sub set_defaults {
    my $obj = shift;
    $obj->has_error(0);
    $obj->is_active(1);
    $obj->is_excerpted(0);
    $obj->total_fails(0);
    $obj->consec_fails(0);
}

sub inject_worker {
    my $self = shift;
    require MT;
    require MT::TheSchwartz;
    require TheSchwartz::Job;
    require Reblog::Util;
    $self->last_fired( time() );
    $self->save;
    my $blog_id = $self->blog_id;
    my $plugin  = MT->component('reblog');
    my $frequency
        = $plugin->get_config_value( 'frequency', 'blog:' . $blog_id );
    $frequency ||= Reblog::Util::DEFAULT_FREQUENCY();
    my $current_epoch;
    $current_epoch = $self->last_fired;
    $current_epoch ||= time();
    my $next_epoch = $current_epoch + ($frequency);

    if ( $next_epoch < time() ) {
        $next_epoch = time() + $frequency;
    }
    my $job = TheSchwartz::Job->new();
    $job->funcname('Reblog::Worker::Import');
    $job->uniqkey( 'reblog_' . $self->id );
    $job->priority( worker_priority() );
    $job->coalesce( $self->id );
    $job->run_after($next_epoch);
    MT::TheSchwartz->insert($job);
}

sub worker_priority {
    use MT::ConfigMgr;
    my $cfg      = MT::ConfigMgr->instance;
    my $priority = $cfg->ReblogWorkerPriority;
    if ($priority) {
        return $priority;
    }
    return DEFAULT_WORKER_PRIORITY;
}

sub increment_error {
    my $self = shift;
    my ($error) = @_;
    $error ||= 'Unknown error';
    my $plugin         = MT->component('reblog');
    my $log            = Reblog::Log::ReblogSourcefeed->new;
    my $total_failures = $self->total_fails;
    $total_failures ||= 0;
    $self->total_fails( $total_failures + 1 );
    my $consecutive_failures = $self->consec_fails;
    $consecutive_failures ||= 0;
    $consecutive_failures++;
    $self->consec_fails($consecutive_failures);
    my $max = $plugin->get_config_value( 'max_failures',
        'blog:' . $self->blog_id );

    if ( ($consecutive_failures) == $max ) {
        $log->message( "Reblog failed to import "
                . $self->url . " "
                . ( $consecutive_failures + 1 )
                . " times (max failures).\n"
                . "SF id: "
                . $self->id );
        $log->metadata($error);
        $log->level( MT::Log::ERROR() );
        $log->category('reblog');
        $log->save or die $log->errstr;
        $self->has_error(1);
        $self->is_active(0);
    }
    else {
        MT->log({
            level    => MT->model('log')->ERROR(),
            class    => 'reblog',
            category => 'import',
            blog_id  => $self->blog_id,
            message  => "Reblog failed to import " . $self->url
                . " from sourcefeed " . $self->label . ', ID ' . $self->id . '.',
        });
    }
    $self->save;
    use MT;
    if ( ($consecutive_failures) >= $max ) {
        MT->run_callbacks( 'plugin_reblog_sourcefeed_failed', $self, $error );
    }
    else {
        MT->run_callbacks( 'plugin_reblog_import_failed', $self, $error );
    }
}

# Build the Reblog Sourcefeed listing framework screen.
sub list_properties {
    return {
        id => {
            label   => 'ID',
            base    => '__virtual.id',
            default => 'optional',
            order   => 1,
        },
        label => {
            label   => 'Label',
            base    => '__virtual.label',
            col     => 'label',
            default => 'display',
            order   => 100,
            sub_fields => [
                {
                    class   => 'is_active',
                    label   => 'Active?',
                    display => 'default',
                },
            ],
            html    => sub {
                # Override the <a/> with label because the default returns a URL
                # that doesn't include the necessary parameters.
                my ( $prop, $obj, $app, $opts ) = @_;
                my $url = $app->uri(
                    mode => 'edit_sourcefeed',
                    args => {
                        id      => $obj->id,
                        blog_id => $obj->blog_id,
                    },
                );
                
                my $label = $obj->label;

                my $is_active = $obj->is_active;
                my $is_active_class = ($is_active) ? 'Active' : 'Inactive';
                my $lc_is_active_class = lc $is_active_class;
                my $is_active_file = ($is_active) ? 'success.gif' : 'draft.gif';
                my $is_active_img = $app->static_path . 'images/status_icons/'
                    . $is_active_file;

                return qq{
                    <span class="icon is_active $lc_is_active_class">
                        <a href="$url">
                            <img alt="$is_active_class"
                                title="$is_active_class"
                                src="$is_active_img" />
                        </a>
                    </span>
                    <span class="title">
                        <a href="$url">$label</a>
                    </span>
                };
            },
        },
        url => {
            label   => 'URL',
            base    => '__virtual.string',
            col     => 'url',
            display => 'default',
            order   => 200,
        },
        is_active => {
            label     => 'Is Active?',
            base      => '__virtual.single_select',
            col       => 'is_active',
            display   => 'none',
            col_class => 'icon',
            single_select_options => [
                {
                    label => 'Active',
                    value => 1,
                },
                {
                    label => 'Inactive',
                    value => 0,
                },
            ],
        },
        last_read => {
            label   => 'Last Read',
            base    => '__virtual.date',
            order   => 300,
            display => 'default',
            col     => 'last_read',
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                my $ts          = $prop->raw(@_) or return '';
                my $date_format = MT::App::CMS::LISTING_DATE_FORMAT();
                my $blog        = $opts->{blog};
                my $is_relative
                    = ( $app->user->date_format || 'relative' ) eq
                    'relative' ? 1 : 0;

                # The last_read column stores the date as seconds past epoch;
                # must convert to a timestamp before formatting.
                $ts = MT::Util::epoch2ts( $blog, $ts );

                return $is_relative
                    ? MT::Util::relative_date( $ts, time, $blog )
                    : MT::Util::format_ts(
                        $date_format,
                        $ts,
                        $blog,
                        $app->user
                            ? $app->user->preferred_language
                            : undef
                    );
            },
        },
        last_fired => {
            label   => 'Last Fired',
            base    => '__virtual.date',
            order   => 301,
            display => 'optional',
            col     => 'last_fired',
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                my $ts          = $prop->raw(@_) or return '';
                my $date_format = MT::App::CMS::LISTING_DATE_FORMAT();
                my $blog        = $opts->{blog};
                my $is_relative
                    = ( $app->user->date_format || 'relative' ) eq
                    'relative' ? 1 : 0;

                # The last_fired column stores the date as seconds past epoch;
                # must convert to a timestamp before formatting.
                $ts = MT::Util::epoch2ts( $blog, $ts );

                return $is_relative
                    ? MT::Util::relative_date( $ts, time, $blog )
                    : MT::Util::format_ts(
                        $date_format,
                        $ts,
                        $blog,
                        $app->user
                            ? $app->user->preferred_language
                            : undef
                    );
            },
        },
        created_by => {
            base    => '__virtual.author_name',
            order   => 700,
            display => 'optional',
        },
        created_on => {
            base    => '__virtual.created_on',
            order   => 701,
            display => 'optional',
        },
        modified_by => {
            base    => '__virtual.author_name',
            label   => 'Modified By',
            order   => 710,
            display => 'optional',
        },
        modified_on => {
            base    => '__virtual.modified_on',
            order   => 711,
            display => 'optional',
        },
        
    };
}

1;

package Reblog::Log::ReblogSourcefeed;
use MT::Log;

our @ISA = qw( MT::Log );

__PACKAGE__->install_properties( { class_type => 'reblog_sourcefeed', } );

sub class_label { MT->translate("Sourcefeed") }

sub description {
    my $log = shift;
    my $msg;
    if ( my $error = $log->metadata ) {
        $msg = $error;
    }
    else {
        $msg = "Unknown error";
    }

    $msg;
}

1;
