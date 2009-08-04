package ConfigAssistant::Plugin;

use strict;

use Carp qw( croak );
use MT::Util
  qw( relative_date offset_time offset_time_list epoch2ts ts2epoch format_ts encode_html dirify );
use ConfigAssistant::Util qw( find_theme_plugin );

sub theme_options {
    my $app     = shift;
    my ($param) = @_;
    my $q       = $app->{query};
    my $blog    = $app->blog;

    $param ||= {};

    my $ts        = $blog->template_set;
    my $plugin    = find_theme_plugin($ts);
    my $cfg       = $app->registry('template_sets')->{$ts}->{options};
    my $types     = $app->registry('config_types');
    my $fieldsets = $cfg->{fieldsets};
    $fieldsets->{__global} = {
        label => sub { "Global Options"; }
    };

    # this is a localized stash for field HTML
    my $fields;
    foreach my $optname ( keys %{$cfg} ) {
        next if $optname eq 'fieldsets';
        my $field = $cfg->{$optname};
        if ( my $cond = $field->{condition} ) {
            if ( !ref($cond) ) {
                $cond = $field->{condition} = $app->handler_to_coderef($cond);
            }
            next unless $cond->();
        }

        my $field_id = $ts . '_' . $optname;
        if ( $types->{ $field->{'type'} } ) {
            my $value =
              $plugin->get_config_value( $field_id, 'blog:' . $blog->id );
            my $out;
            $field->{fieldset} = '__global' unless defined $field->{fieldset};
            my $show_label =
              defined $field->{show_label} ? $field->{show_label} : 1;
            $out .=
                '  <div id="'
              . $field_id
              . '" class="field field-left-label pkg field-type-'
              . $field->{type} . '">' . "\n";
            $out .= "    <div class=\"field-header\">\n";
            $out .=
                "      <label for=\"$field_id\">"
              . &{ $field->{label} }
              . "</label>\n"
              if $show_label;
            $out .= "    </div>\n";
            $out .= "    <div class=\"field-content\">\n";
            my $hdlr =
              MT->handler_to_coderef( $types->{ $field->{'type'} }->{handler} );
            $out .= $hdlr->( $app, $field_id, $field, $value );

            if ( $field->{hint} ) {
                $out .=
                  "      <div class=\"hint\">" . $field->{hint} . "</div>\n";
            }
            $out .= "    </div>\n";
            $out .= "  </div>\n";
            my $fs = $field->{fieldset};
            push @{ $fields->{$fs} }, $out;
        }
        else {
            MT->log(
                {
                    message => 'Unknown config type encountered: '
                      . $field->{'type'}
                }
            );
        }
    }
    my @loop;
    my $count = 0;
    my $html;
    foreach my $set (
        sort {
            ( $fieldsets->{$a}->{order} || 999 )
              <=> ( $fieldsets->{$b}->{order} || 999 )
        } keys %$fieldsets
      )
    {
        next unless $fields->{$set} || $fieldsets->{$set}->{template};
        my $label     = &{ $fieldsets->{$set}->{label} };
        my $innerhtml = '';
        if ( my $tmpl = $fieldsets->{$set}->{template} ) {
            my $txt = $plugin->load_tmpl($tmpl);
            my $filter =
                $fieldsets->{$set}->{format}
              ? $fieldsets->{$set}->{format}
              : '__default__';
            $txt = MT->apply_text_filters( $txt->text(), [$filter] );
            $innerhtml = $txt;
            $html .= $txt;
        }
        else {
            $html .= "<fieldset>";
            $html .= "<h3>" . $label . "</h3>";
            foreach ( @{ $fields->{$set} } ) {
                $innerhtml .= $_;
            }
            $html .= $innerhtml;
            $html .= "</fieldset>";
        }
        push @loop,
          {
            '__first__' => ( $count++ == 0 ),
            id          => dirify($label),
            label       => $label,
            content     => $innerhtml,
          };
    }
    $param->{html}       = $html;
    $param->{fieldsets}  = \@loop;
    $param->{blog_id}    = $blog->id;
    $param->{plugin_sig} = $plugin->{plugin_sig};
    $param->{saved}      = $q->param('saved');
    return $app->load_tmpl( 'theme_options.tmpl', $param );
}

sub type_text {
    my $app = shift;
    my ( $field_id, $field, $value ) = @_;
    return
        "      <input type=\"text\" name=\"$field_id\" value=\""
      . encode_html($value)
      . "\" class=\"full-width\" />\n";
}

sub type_textarea {
    my $app = shift;
    my ( $field_id, $field, $value ) = @_;
    my $out;
    $out .= "      <textarea name=\"$field_id\" class=\"full-width\" rows=\""
      . $field->{rows} . "\" />";
    $out .= encode_html($value);
    $out .= "      </textarea>\n";
    return $out;
}

sub type_radio {
    my $app = shift;
    my ( $field_id, $field, $value ) = @_;
    my $out;
    my @values = split( ",", $field->{values} );
    $out .= "      <ul>\n";
    foreach (@values) {
        $out .=
            "        <li><input type=\"radio\" name=\"$field_id\" value=\"$_\""
          . ( $value eq $_ ? " checked=\"checked\"" : "" )
          . " class=\"rb\" />"
          . $_
          . "</li>\n";
    }
    $out .= "      </ul>\n";
    return $out;
}

sub type_radio_image {
    my $app = shift;
    my ( $field_id, $field, $value ) = @_;
    my $out;
    my $static = $app->config->StaticWebPath;
    $out .= "      <ul class=\"pkg\">\n";
    while ( $field->{values} =~ /\"([^\"]*)\":\"([^\"]*)\",?/g ) {
        $out .=
            "        <li><input type=\"radio\" name=\"$field_id\" value=\"$2\""
          . ( $value eq $2 ? " checked=\"checked\"" : "" )
          . " class=\"rb\" />"
          . "<img src=\""
          . $static
          . $1
          . "\" /><br />$2"
          . "</li>\n";
    }
    $out .= "      </ul>\n";
    return $out;
}

sub type_select {
    my $app = shift;
    my ( $field_id, $field, $value ) = @_;
    my $out;
    my @values = split( ",", $field->{values} );
    $out .= "      <select name=\"$field_id\">\n";
    foreach (@values) {
        $out .=
            "        <option"
          . ( $value eq $_ ? " selected" : "" )
          . ">$_</option>\n";
    }
    $out .= "      </select>\n";
    return $out;
}

sub type_blogs {
    my $app = shift;
    my ( $field_id, $field, $value ) = @_;
    my $out;
    my @blogs = MT->model('blog')->load( {}, { sort => 'name' } );
    $out .= "      <select name=\"$field_id\">\n";
    $out .=
        "        <option value=\"0\" "
      . ( 0 == $value ? " selected" : "" )
      . ">None Selected</option>\n";
    foreach (@blogs) {
        $out .=
            "        <option value=\""
          . $_->id . "\" "
          . ( $value == $_->id ? " selected" : "" ) . ">"
          . $_->name
          . "</option>\n";
    }
    $out .= "      </select>\n";
    return $out;
}

sub type_checkbox {
    my $app = shift;
    my ( $field_id, $field, $value ) = @_;
    my $out;
    $out .= "      <input type=\"checkbox\" name=\"$field_id\" value=\"1\" "
      . ( $value ? "checked ." : "" ) . "/>\n";
    return $out;
}

sub _hdlr_field_value {
    my $plugin = shift;
    my ( $ctx, $args ) = @_;
    my $plugin_ns = $ctx->stash('plugin_ns');
    my $field     = $ctx->stash('field')
      or return _no_field($ctx);
    $plugin = MT->component($plugin_ns);    # is this necessary?

    my $value;
    my $blog_id = $ctx->var('blog_id');
    my $blog    = $ctx->stash('blog');
    if ( !$blog && $blog_id ) {
        $blog = MT->model('blog')->load($blog_id);
    }
    if ( $blog && $blog->id ) {
        $value = $plugin->get_config_value( $field, 'blog:' . $blog->id );
    }
    else {
        $value = $plugin->get_config_value($field);
    }
    return $args->{default} if ( $args->{default} && $value eq '' );
    return $value;
}

sub _hdlr_field_cond {
    my $plugin = shift;
    my ( $ctx, $args ) = @_;
    my $plugin_ns = $ctx->stash('plugin_ns');
    my $field     = $ctx->stash('field')
      or return _no_field($ctx);
    my $blog_id = $ctx->var('blog_id');
    my $blog    = $ctx->stash('blog');
    if ( !$blog && $blog_id ) {
        $blog = MT->model('blog')->load($blog_id);
    }
    $plugin = MT->component($plugin_ns);    # is this necessary?

    my $value = $plugin->get_config_value( $field, 'blog:' . $blog->id );
    if ($value) {
        return $ctx->_hdlr_pass_tokens(@_);
    }
    else {
        return $ctx->_hdlr_pass_tokens_else(@_);
    }
}

sub _no_field {
    return $_[0]->error(
        MT->translate(
"You used an '[_1]' tag outside of the context of the correct content; ",
            $_[0]->stash('tag')
        )
    );
}

sub tag_config_form {
    my ( $ctx, $args, $cond ) = @_;
    my $app  = MT->app;
    my $html = '';
    my $id   = $args->{'id'};
    my $cfg  = $app->registry( 'plugin_config', $id );
    foreach my $key ( sort keys %$cfg ) {
        my $plugin   = delete $cfg->{$key}->{'plugin'};
        my $fieldset = $cfg->{$key};
        $html .= "<fieldset>\n";
        my $label = delete $fieldset->{'label'};
        if ($label) {
            $html .= "  <h3>" . &$label . "</h3>\n";
        }
        my $fs_text = delete $fieldset->{'description'};
        if ($fs_text) {
            $html .= "  <p>" . &$fs_text . "</p>\n";
        }
        foreach my $field_id ( sort keys %$fieldset ) {
            my $field = $fieldset->{$field_id};
            my $value =
              $plugin->get_config_value( $field_id, 'blog:' . $app->blog->id );
            my $show_label =
              $field->{'show_label'} ? &{ $field->{'show_label'} } : 1;
            $html .=
                '  <div id="'
              . $field_id
              . '" class="field field-left-label pkg">' . "\n";
            $html .= "    <div class=\"field-header\">\n";
            $html .=
                "      <label for=\"$id-$field_id\">"
              . &{ $field->{'label'} }
              . "</label>\n"
              if $show_label;
            $html .= "    </div>\n";
            $html .= "    <div class=\"field-content\">\n";

            if ( $field->{'type'} eq 'text' ) {
                $html .=
                    "      <input type=\"text\" name=\"$field_id\" value=\""
                  . encode_html($value)
                  . "\" class=\"full-width\" />\n";

            }
            elsif ( $field->{'type'} eq 'textarea' ) {
                $html .=
"      <textarea name=\"$field_id\" class=\"full-width\" rows=\""
                  . $field->{rows} . "\" />";
                $html .= encode_html($value);
                $html .= "</textarea>\n";

            }
            elsif ( $field->{'type'} eq 'radio' ) {
                my @values = split( ",", $field->{values} );
                $html .= "      <ul>\n";
                foreach (@values) {
                    $html .=
"        <li><input type=\"radio\" name=\"$field_id\" value=\"$_\""
                      . ( $value eq $_ ? " checked=\"checked\"" : "" )
                      . " class=\"rb\" />"
                      . $_
                      . "</li>\n";
                }
                $html .= "      </ul>\n";

            }
            elsif ( $field->{'type'} eq 'select' ) {
                my @values = split( ",", $field->{values} );
                $html .= "      <select name=\"$field_id\">\n";
                foreach (@values) {
                    $html .=
                        "        <option"
                      . ( $value eq $_ ? " selected" : "" )
                      . ">$_</option>\n";
                }
                $html .= "      </select>\n";

            }
            elsif ( $field->{'type'} eq 'checkbox' ) {
                $html .=
"      <input type=\"checkbox\" name=\"$field_id\" value=\"1\" "
                  . ( $value ? "checked ." : "" ) . "/>\n";

            }
            elsif ( $field->{'type'} eq 'blogs' ) {
                my @blogs = MT->model('blog')->load( {}, { sort => 'name' } );
                $html .= "      <select name=\"$field_id\">\n";
                $html .=
                    "        <option value=\"0\" "
                  . ( 0 == $value ? " selected" : "" )
                  . ">None Selected</option>\n";
                foreach (@blogs) {
                    $html .=
                        "        <option value=\""
                      . $_->id . "\" "
                      . ( $value == $_->id ? " selected" : "" ) . ">"
                      . $_->name
                      . "</option>\n";
                }
                $html .= "      </select>\n";
            }

            if ( $field->{hint} ) {
                $html .= "      <br /><span>" . $field->{hint} . "</span>\n";
            }
            $html .= "    </div>\n";
            $html .= "  </div>\n";
        }
    }
    return $html;
}

1;

__END__
