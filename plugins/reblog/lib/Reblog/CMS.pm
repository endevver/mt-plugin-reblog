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
# $Id: CMS.pm 17902 2009-04-07 02:16:15Z steve $

package Reblog::CMS;
use strict;
use warnings;
use Storable;

# This is the blog-level Reblog configurations settings, available at
# Manage > Reblog.
sub config {
    my $app   = shift;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'reblog' ) ) {
        return $app->error('You cannot configure Reblog for this blog.');
    }
    my $plugin = MT->component('reblog');
    my $tmpl   = $plugin->load_tmpl('config.tmpl');
    my $param;

    die $app->error('Required "blog_id" parameter is missing.')
        if !$app->param('blog_id');

    my $blog = MT->model('blog')->load( $app->param('blog_id') )
        or die $app->error(
            'A blog with the ID ' . $app->param('blog_id') . ' was not found.'
        );

    # This is used frequently when getting and setting plugin options. No need
    # to keep re-building it.
    my $blog_shortcut = 'blog:' . $blog->id;

    # Save the options as specified.
    if ( $app->param('save') ) {
        # Save the original values so that they can be compared to the new
        # values, so that any difference can be recorded to the Activity Log.
        my $old_config = $plugin->get_config_hash($blog_shortcut);

        my $frequency = $app->param('frequency');
        if ( !$frequency || $frequency < 15 * 60 ) {
            $frequency = 15 * 60;
        }
        $frequency = sprintf( '%u', $frequency );
        $plugin->set_config_value(
            'frequency',
            $app->param('frequency'),
            $blog_shortcut
        );
        $plugin->set_config_value(
            'default_author',
            $app->param('reblog_author'),
            $blog_shortcut
        );
        if (   $app->param('max_failures') =~ m/^\d+$/
            && $app->param('max_failures') )
        {
            my $max_failures = $app->param('max_failures');
            ( $max_failures < 1 ) && ( $max_failures = 1 );
            $plugin->set_config_value(
                'max_failures',
                $max_failures,
                $blog_shortcut
            );
        }
        if ( $app->param('import_categories') ) {
            $plugin->set_config_value( 'import_categories', 1, $blog_shortcut );
        }
        else {
            $plugin->set_config_value( 'import_categories', 0, $blog_shortcut );
        }

        if ( $app->param('import_feed_title_as_category') ) {
            $plugin->set_config_value( 'import_feed_title_as_category', 1,
                $blog_shortcut );
        }
        else {
            $plugin->set_config_value( 'import_feed_title_as_category', 0,
                $blog_shortcut );
        }

        if ( $app->param('rebuild_individual') ) {
            $plugin->set_config_value( 'rebuild_individual', 1, $blog_shortcut );
        }
        else {
            $plugin->set_config_value( 'rebuild_individual', 0, $blog_shortcut );
        }

        if ( $app->param('display_entry_details') ) {
            $plugin->set_config_value( 'display_entry_details', 1,
                $blog_shortcut );
        }
        else {
            $plugin->set_config_value( 'display_entry_details', 0,
                $blog_shortcut );
        }

        $plugin->set_config_value(
            'entry_status',
            $app->param('entry_status'),
            $blog_shortcut
        );

        # Get the hash of the new values so that we can compare to the old
        # values to determine what changed and what to record to the Activity
        # Log.
        my $new_config = $plugin->get_config_hash($blog_shortcut);

        local $Storable::canonical = 1;
        if ( Storable::freeze($old_config) ne Storable::freeze($new_config) ) {
            my @changed_vals;
            foreach my $val ( keys $new_config ) {
                # MT->log("Test: ".$new_config->$val);
                if ($new_config->{$val} ne $old_config->{$val}) {
                    push @changed_vals, $val;
                }
            }

            # Create a metadata field message about exactly what has changed.
            my $metadata = '';
            foreach my $val (@changed_vals) {
                $metadata .= "Updated $val: " . $new_config->{$val}
                    . "; original: " . $old_config->{$val} . ". \n";
            }

            $app->log({
                level     => $app->model('log')->INFO(),
                class     => 'reblog',
                category  => 'save_blog_config',
                blog_id   => $blog->id,
                author_id => $app->user->id,
                message   => 'The Reblog configuration in the "' . $blog->name
                    . '" blog has changed.',
                metadata  => $metadata,
            });
        }
    }

    use MT::Author;
    my $author_iter = MT::Author->load_iter(
        {},
        {   sort => 'name',
            join => MT::Permission->join_on(
                'author_id',
                { blog_id => $blog->id },
                { unique  => 1 }
            )
        }
    );
    my @author_loop;
    while ( my $a = $author_iter->() ) {
        next unless $a->permissions($blog)->has('publish_post')
            || $a->can_administer();
        my $row;
        my $shown = $a->name;
        if ( $a->nickname ) { $shown .= ' (' . $a->nickname . ')'; }
        $row->{author_name} = $shown;
        $row->{author_id}   = $a->id;
        push @author_loop, $row;
    }
    $param->{author_loop}    = \@author_loop;

    $param->{frequency_loop} = [
        { frequency => 'Every 24 hours',   seconds => 24 * 60 * 60 },
        { frequency => 'Every 12 hours',   seconds => 12 * 60 * 60 },
        { frequency => 'Every 6 hours',    seconds => 6 * 60 * 60 },
        { frequency => 'Every 3 hours',    seconds => 3 * 60 * 60 },
        { frequency => 'Hourly',           seconds => 60 * 60 },
        { frequency => 'Every 30 minutes', seconds => 30 * 60 },
        { frequency => 'Every 15 minutes', seconds => 15 * 60 },
        { frequency => 'Every 10 minutes', seconds => 10 * 60 },
        { frequency => 'Every 5 minutes',  seconds => 5 * 60 }
    ];

    $param->{blog_name} = $blog->name;
    $param->{display_entry_details}
        = $plugin->get_config_value( 'display_entry_details', $blog_shortcut );
    $param->{default_author_id}
        = $plugin->get_config_value( 'default_author', $blog_shortcut );
    $param->{default_frequency}
        = $plugin->get_config_value( 'frequency', $blog_shortcut );
    $param->{default_max_failures}
        = $plugin->get_config_value( 'max_failures', $blog_shortcut );
    $param->{rebuild_individual}
        = $plugin->get_config_value( 'rebuild_individual', $blog_shortcut );
    $param->{import_categories}
        = $plugin->get_config_value( 'import_categories', $blog_shortcut );
    $param->{import_feed_title_as_category}
        = $plugin->get_config_value(
            'import_feed_title_as_category',
            $blog_shortcut
        );
    $param->{entry_status}
        = $plugin->get_config_value( 'entry_status', $blog_shortcut );

    # Status messaging.
    $param->{saved} = $app->param('save');

    $app->build_page( $tmpl, $param );
}

# On the Manage Sourcefeeds screen is an Import list action/button that will
# allow admins to import the selected sourcefeeds, creating entries,
# republishing, etc.
sub import_sourcefeeds {
    my $app = shift;
    $app->validate_magic() or return;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'sourcefeeds' ) ) {
        return $app->error('You cannot configure sourcefeeds for this blog.');
    }
    my @ids = $app->param('id');
    use Reblog::ReblogSourcefeed;
    my @feeds;
    foreach my $id (@ids) {
        my @load = Reblog::ReblogSourcefeed->load(
            { id => $id, blog_id => $app->blog->id } );
        my $feed = shift @load;
        ($feed) && push @feeds, $feed;
    }
    my $blog = $app->blog;
    my $res;
    if (@feeds) {
        use Reblog::Util;
        $res = Reblog::Util::do_import( $app, '', $blog, @feeds );
        if ( $app->errstr ) {
            return $app->error( $app->errstr );
        }
    }
    else {
        return $app->error('Blog mismatch or no feeds selected');
    }
    my $plugin = MT->component('reblog');
    my $tmpl   = $plugin->load_tmpl('manual_import.tmpl');
    my $param;
    my $mt = MT->instance;
    $param->{script_url}     = $mt->uri;
    $param->{blog_id}        = $blog->id;
    $param->{reblog_message} = $res;
    $app->build_page( $tmpl, $param );
}

# Save the sourcefeed, from the Edit Sourcefeed screen.
sub save_sourcefeed {
    my $app   = shift;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'sourcefeeds' ) ) {
        return $app->error('You cannot configure sourcefeeds for this blog.');
    }
    $app->forward('save');
}

sub cms_entry_preview_callback {
    my ( $cb, $app, $entry, $data ) = @_;
    unless ( $app->param('reblog_manual_edit') ) {
        return;
    }
    my @editablevals
        = qw( annotation source_title source_link via_link thumbnail_url thumbnail_link enclosure_url );
    foreach my $val (@editablevals) {
        push @{$data}, { data_name => $val, data_value => $app->param($val) };
    }
    push @{$data}, { data_name => 'reblog_manual_edit', data_value => 1 };
}

sub cms_sourcefeed_presave_callback {
    my ( $cb, $app, $feed, $orig ) = @_;
    unless ( $app->param('is_active') ) {
        $feed->is_active(0);
    }
    unless ( $app->param('is_excerpted') ) {
        $feed->is_excerpted(0);
    }
    if ( $app->param('clear_errors') ) {
        $feed->has_error(0);
        $feed->consec_fails(0);
    }
    return 1;
}

# Log user activity with sourcefeeds.
sub cms_sourcefeed_postsave_callback {
    my ( $cb, $app, $obj, $orig ) = @_;
    my $message  = '';
    my $metadata = '';

    # Are $obj and $orig different? If yes, log it. If nothing changed then
    # there is no reason to log anything -- just return.
    local $Storable::canonical = 1;
    return 1
        if Storable::freeze( $obj->column_values )
            eq Storable::freeze( $orig->column_values );

    # Is this a newly-added Sourcefeed?
    if ( ! $orig->id ) {
        $message = 'A new Reblog Sourcefeed was saved: ' . $obj->label
            . ' (ID:' . $obj->id . ').';
    }
    # This is not a new sourcefeed. Compare the objects to find what changed.
    else {
        $message = 'The Reblog Sourcefeed "' . $obj->label . '" was updated.';
        my @changed_columns;
        foreach my $column_name ( keys $obj->column_values ) {
            # The modified_on timestamp is always updated to reflect the save.
            next if $column_name eq 'modified_on';

            # Save the column name
            if ($obj->$column_name ne $orig->$column_name) {
                push @changed_columns, $column_name;
            }
        }

        # Create a metadata field message about exactly what has changed.
        foreach my $column_name (@changed_columns) {
            $metadata .= "Updated $column_name: " . $obj->$column_name
                . "; original: " . $orig->$column_name . ". \n";
        }
    }

    $app->log({
        level     => $app->model('log')->INFO(),
        class     => 'reblog',
        category  => 'save_sourcefeed',
        blog_id   => $obj->blog_id,
        author_id => $app->user->id,
        message   => $message,
        metadata  => $metadata,
    });
}

# The sourcefeed list view, availabe at Manage > Sourcefeeds.
sub list_sourcefeeds {
    use Reblog::ReblogSourcefeed;
    my ($app) = @_;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'sourcefeeds' ) ) {
        return $app->error('You cannot configure sourcefeeds for this blog.');
    }
    my $blog    = $app->blog;
    my $plugin  = MT->component('reblog');
    my $blog_id = $blog->id;

    $app->listing(
        {   type  => 'ReblogSourcefeed',
            terms => { blog_id => $blog_id, },
            args  => {
                sort      => 'label',
                direction => 'ascend'
            },
            code => sub {
                my ( $obj, $row ) = @_;
            },
        }
    );
}

# When on the Edit Sourcefeed screen, there's a "Validate" button to validate
# the URL entered, to help ensure Reblog will work. Clicking that Validate
# button calls this method, which returns an AJAX response to be displayed
# inline.
sub validate_json {
    use Reblog::Util;
    use JSON;
    my $app   = shift;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'sourcefeeds' ) ) {
        return $app->error('You cannot configure sourcefeeds for this blog.');
    }
    my $sourcefeed = $app->param('sourcefeed');
    my $valid;
    my $res;
    if ($sourcefeed) {
        $valid = 0;
        eval { $valid = Reblog::Util::validate_feed( $app, $sourcefeed ); };
        if ($@) {
            $valid = 0;
        }
    }
    else {
        $app->error('No sourcefeed given');
    }
    if ($valid) {
        $res->{success} = 1;
        my $err = $app->errstr;
        if ($err) {
            $err =~ s/^\n//;
            $err =~ s/\n$//;
            use MT::Util;
            $err = MT::Util::encode_html($err);
            $res->{errstr} = MT::Util::encode_html($err);
        }
    }
    else {
        $res->{success} = 0;
        my $err = $app->errstr;
        $err ||= 'Unknown error';
        $err =~ s/^\n//;
        $err =~ s/\n$//;
        use MT::Util;
        $err = MT::Util::encode_html($err);
        $res->{errstr} = MT::Util::encode_html($err);
    }
    $app->{no_print_body} = 1;
    $app->send_http_header('text/javascript');
    if ( $JSON::VERSION > 2 ) {
        $app->print( JSON::to_json($res) );
    }
    else {
        $app->print( JSON::objToJson($res) );
    }
    1;
}

# The Edit Sourcefeed screen.
sub edit_sourcefeed {
    my $app   = shift;
    my $perms = $app->permissions;
    unless ( check_perms( $perms, $app->user, 'sourcefeeds' ) ) {
        return $app->error('You cannot configure sourcefeeds for this blog.');
    }
    my $q      = $app->param;
    my $plugin = MT->component('reblog');
    my $tmpl   = $plugin->load_tmpl('edit_ReblogSourcefeed.tmpl');

    my $class = $app->model('ReblogSourcefeed');
    my %param = ();

    $param{object_type} = 'ReblogSourcefeed';
    my $id = $q->param('id');
    my $obj;
    if ($id) {
        $obj = $class->load($id);
    }
    else {
        $obj = $class->new;
    }

    my $cols = $class->column_names;

    # Populate the param hash with the object's own values
    for my $col (@$cols) {
        $param{$col}
            = defined $q->param($col) ? $q->param($col) : $obj->$col();
    }

    if ( $class->can('class_label') ) {
        $param{object_label} = $class->class_label;
    }
    if ( $class->can('class_label_plural') ) {
        $param{object_label_plural} = $class->class_label_plural;
    }

    $param{saved} = $app->param('saved');

    $app->build_page( $tmpl, \%param );
}

# Called by CMSPostSave.entry
sub reblog_save {
    my ( $cb, $app, $obj ) = @_;
    my $plugin = MT->component('reblog');
    unless ( $app->blog && $obj->blog_id ) {
        return;
    }
    unless ( $app->param('reblog_manual_edit') ) {
        return;
    }
    my ($blogid,        $via_link,         $source_title,
        $source_link,   $thumbnail_link,   $thumbnail_url,
        $enclosure_url, $enclosure_length, $enclosure_type,
        $annotation
    );

    $blogid           = $obj->blog_id;
    $via_link         = $app->param('via_link');
    $source_title     = $app->param('source_title');
    $source_link      = $app->param('source_link');
    $thumbnail_link   = $app->param('thumbnail_link');
    $thumbnail_url    = $app->param('thumbnail_url');
    $enclosure_url    = $app->param('enclosure_url');
    $enclosure_length = $app->param('enclosure_length');
    $enclosure_type   = $app->param('enclosure_type');
    $annotation       = $app->param('annotation');
    my $reblog = Reblog::ReblogData->load( { entry_id => $obj->id } );

    if ($reblog) {
        $reblog->via_link(       $via_link         );
        $reblog->src_url(        $source_link      );
        $reblog->src_title(      $source_title     );
        $reblog->thumbnail_link( $thumbnail_link   );
        $reblog->thumbnail_url(  $thumbnail_url    );
        $reblog->encl_url(       $enclosure_url    );
        $reblog->encl_type(      $enclosure_type   );
        $reblog->encl_length(    $enclosure_length );
        $reblog->annotation(     $annotation       );

        $reblog->save;
    }
    else {

        # create a new reblog row
        my $entry = MT::Entry->load( { id => $obj->id } );

        my $user = $app->user;

        my $rbd = Reblog::ReblogData->new;
        if ($via_link) {
            $rbd->via_link($via_link);
        }
        $rbd->src_url($source_link);
        if ($source_title) {
            $rbd->src_title($source_title);
        }
        else {
            $rbd->src_title( $entry->title );
        }
        $rbd->thumbnail_link( $thumbnail_link    );
        $rbd->thumbnail_url(  $thumbnail_url     );
        $rbd->encl_url(       $enclosure_url     );
        $rbd->encl_length(    $enclosure_length  );
        $rbd->encl_type(      $enclosure_type    );
        $rbd->entry_id(       $obj->id           );
        $rbd->src_created_on( $entry->created_on );
        $rbd->created_on(     $entry->created_on );

        # TODO - not obviously exposed in app
        $rbd->src_author(    $user->nickname );
        $rbd->link(          $source_link    );
        $rbd->guid(          $entry->atom_id );
        $rbd->src(           $source_title   );
        $rbd->src_feed_url(  '#'             );
        $rbd->sourcefeed_id( 0               );
        $rbd->blog_id(       $blogid         );
        $rbd->save;
    }
}

# The Manage Reblog configuration screen (at Manage > Reblog) saves it's values
# to the blog-level plugindata object, just like plugin Settings.
sub save_config {    # Translate default author's author_name into author id
    my $plugin = shift;
    my ( $param, $scope ) = @_;
    my $found;
    if ( $param->{default_author} ) {
        my @authors
            = MT::Author->load( { name => $param->{default_author} } );
        unless (@authors) {
            @authors = MT::Author->load( { id => $param->{default_author} } );
        }
        for (@authors) {
            $param->{default_author} = $_->id;
            $found = 1;
            last;
        }
    }
    if ( !$found ) {
        $param->{default_author} = '';
    }
    return $plugin->SUPER::save_config( $param, $scope );
}

sub inline_edit_entry {
    my ( $callback, $app, $param, $tmpl ) = @_;
    my $entry_id = $param->{id};
    my $plugin   = MT->component('reblog');
    unless ( $app->blog ) {
        return;
    }
    unless (
        $plugin->get_config_value(
            'display_entry_details', 'blog:' . $app->blog->id
        )
        )
    {
        return;
    }
    my $reblog_data;
    $reblog_data = Reblog::ReblogData->load( { entry_id => $param->{id} } );
    $reblog_data ||= Reblog::ReblogData->new
        ;    # not going to save this, just need an object to avoid errors
    my $reblog_setting = $tmpl->createElement(
        'app:setting',
        {   id          => 'reblog_info',
            required    => 0,
            label       => 'Reblog Information',
            shown       => 1,
            label_class => 'top-label'
        }
    );
    my $panel_tmpl = $plugin->load_tmpl('editentry_reblog_panel.tmpl');
    my $inner      = $panel_tmpl->text;
    use HTML::Template;
    my $addition
        = HTML::Template->new_scalar_ref( \$inner, option => 'value' );

    if ( $app->param('reedit') ) {
        $addition->param( ANNOTATION     => $app->param('annotation') );
        $addition->param( SOURCE_TITLE   => $app->param('source_title') );
        $addition->param( SOURCE_LINK    => $app->param('source_link') );
        $addition->param( VIA_LINK       => $app->param('via_link') );
        $addition->param( THUMBNAIL_LINK => $app->param('thumbnail_link') );
        $addition->param( THUMBNAIL_URL  => $app->param('thumbnail_url') );
        $addition->param( ENCLOSURE_URL  => $app->param('enclosure_url') );
    }
    else {
        $addition->param( ANNOTATION     => $reblog_data->annotation );
        $addition->param( SOURCE_TITLE   => $reblog_data->src_title );
        $addition->param( SOURCE_LINK    => $reblog_data->src_url );
        $addition->param( VIA_LINK       => $reblog_data->via_link );
        $addition->param( THUMBNAIL_LINK => $reblog_data->thumbnail_link );
        $addition->param( THUMBNAIL_URL  => $reblog_data->thumbnail_url );
        $addition->param( ENCLOSURE_URL  => $reblog_data->encl_url );
    }
    $reblog_setting->innerHTML( $addition->output );
    my $keywords_field = $tmpl->getElementById('keywords');
    $tmpl->insertAfter( $reblog_setting, $keywords_field );
}

# On each screen in Reblog, permissions are check to see if the user has
# adequate permission to do what they're trying to do.
sub check_perms {
    my ( $perms, $author, $type ) = @_;
    my $plugin = MT->component('reblog');
    my $app    = MT->instance;

    # If the user has moved from the blog level to the system level, be sure to
    # redirect them to the dashboard.
    if (!$app->blog) {
        return $app->redirect($app->mt_uri . '?__mode=dashboard&blog_id=0');
    }

    unless ( $perms && $author && $type ) {
        return;
    }
    my $restrict;
    if ( $type eq 'reblog' ) {
        $restrict = $plugin->get_config_value( 'restrict_reblog', 'system' );
    }
    else {
        $restrict
            = $plugin->get_config_value( 'restrict_sourcefeeds', 'system' );
    }
    if ($restrict) {
        return $author->is_superuser;
    }
    else {
        return $perms->can_administer_blog;
    }
}

# The menu condition to check if the user in context has adequate permission to
# view the Tools > Reblog Configuration menu item.
sub menu_permission_reblog {
    my $app = MT->instance;
    unless ($app) {
        return 0;
    }
    my $blog   = $app->blog;
    my $author = $app->user;
    my $plugin = MT->component('reblog');
    my $perms  = $app->permissions;
    unless ( $blog && $app && $plugin && $perms ) {
        return 0;
    }
    my $restrict = $plugin->get_config_value( 'restrict_reblog', 'system' );
    if ($restrict) {
        return $author->is_superuser;
    }
    else {
        return $perms->can_administer_blog;
    }
}

# The menu condition to check if the user in context has adequate permission to
# view the Tools > Reblog Sourcefeeds menu item. Check for the required version
# of MT first, then consider permissions.
sub menu_permission_sourcefeeds_mt5 {
    return 0 if MT->product_version =~ /^4/; # MT5 only
    return _menu_permission_sourcefeeds();
}

sub menu_permission_sourcefeeds_mt4 {
    return 0 if MT->product_version !~ /^4/; # MT4 only
    return _menu_permission_sourcefeeds();
}

# Called by the version-specific check, above.
sub _menu_permission_sourcefeeds {
    my $app = MT->instance;
    unless ($app) {
        return 0;
    }
    my $blog   = $app->blog;
    my $author = $app->user;
    my $plugin = MT->component('reblog');
    my $perms  = $app->permissions;
    unless ( $blog && $app && $plugin && $perms ) {
        return 0;
    }
    my $restrict
        = $plugin->get_config_value( 'restrict_sourcefeeds', 'system' );
    if ($restrict) {
        return $author->is_superuser;
    }
    else {
        return $perms->can_administer_blog;
    }
}

1;
