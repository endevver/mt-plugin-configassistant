package ConfigAssistant::Init;

use strict;
use ConfigAssistant::Util qw( find_theme_plugin );

sub plugin {
    return MT->component('ConfigAssistant');
}

sub init_app {
    my $plugin = shift;
    my ($app) = @_;
    return if $app->id eq 'wizard';
    my $r = $plugin->registry;
    $r->{tags} = sub { load_tags($plugin) };
}

sub init_request {
    my $callback = shift;
    my $app      = MT->instance;
    return if $app->id eq 'wizard';

    # For each plugin, convert options into settings
    for my $sig ( keys %MT::Plugins ) {
        my $plugin = $MT::Plugins{$sig};
        my $obj    = $MT::Plugins{$sig}{object};
        my $r      = $obj->{registry};
        my @sets   = keys %{ $r->{'template_sets'} };
        foreach my $set (@sets) {
            if ( $r->{'template_sets'}->{$set}->{'options'} ) {
                foreach my $opt (
                    keys %{ $r->{'template_sets'}->{$set}->{'options'} } )
                {
                    next if ( $opt eq 'fieldsets' );
                    my $option =
                      $r->{'template_sets'}->{$set}->{'options'}->{$opt};

# To avoid option names that may collide with other options in other template sets
# settings are derived by combining the name of the template set and the option's
# key.
                    my $optname = $set . '_' . $opt;
                    if ( $obj->{'registry'}->{'settings'}->{$optname} ) {

#			MT->log({blog_id => ($app->blog ? $app->blog->id : 0),
#				 level => MT::Log::WARNING(),
#				 message => "The plugin (".$r->{name}.") defines two options with the same key ($opt) in the same template set ($set)."});
                    }
                    else {

          #			MT->log({blog_id => ($app->blog ? $app->blog->id : 0),
          #				 level => MT::Log::WARNING(),
          #				 message => "Registering $optname for plugin (".$r->{name}.")"});
                        $obj->{'registry'}->{'settings'}->{$optname} = {
                            scope => 'blog',
                            %$option,
                        };
                    }
                }
            }
        }
    }
    1;
}

sub uses_config_assistant {

    #    local $@;
    my $blog = MT->instance->blog;
    return 0 if !$blog;
    my $ts  = MT->instance->blog->template_set;
    my $app = MT::App->instance;
    return 1 if $app->registry('template_sets')->{$ts}->{options};
    return 0;
}

sub load_tags {
    my $app  = MT->app;
    my $cfg  = $app->registry('plugin_config');
    my $tags = {};

# First load tags that correspond with Plugin Settings
# TODO: this struct needs to be abstracted out to be similar to template set options
    foreach my $plugin_id ( keys %$cfg ) {
        my $plugin_cfg = $cfg->{$plugin_id};
        my $p          = delete $cfg->{$plugin_id}->{'plugin'};
        foreach my $key ( keys %$plugin_cfg ) {
            my $fieldset = $plugin_cfg->{$key};
            delete $fieldset->{'label'};
            foreach my $field_id ( keys %$fieldset ) {
                my $field = $fieldset->{$field_id};
                my $tag   = $field->{tag};
                if ( $tag =~ s/\?$// ) {
                    $tags->{block}->{$tag} = sub {
                        $_[0]->stash( 'field',     $field_id );
                        $_[0]->stash( 'plugin_ns', $p->id );
                        runner( '_hdlr_field_cond', 'ConfigAssistant::Plugin',
                            @_ );
                    };
                }
                elsif ( $tag ne '' ) {
                    $tags->{function}->{$tag} = sub {
                        $_[0]->stash( 'field',     $field_id );
                        $_[0]->stash( 'plugin_ns', $p->id );
                        runner( '_hdlr_field_value', 'ConfigAssistant::Plugin',
                            @_ );
                    };
                }
            }
        }
    }

    # Now register template tags for each of the template set options.
    for my $sig ( keys %MT::Plugins ) {
        my $plugin = $MT::Plugins{$sig};
        my $obj    = $MT::Plugins{$sig}{object};
        my $r      = $obj->{registry};
        my @sets   = keys %{ $r->{'template_sets'} };
        foreach my $set (@sets) {
            if ( $r->{'template_sets'}->{$set}->{'options'} ) {
                foreach my $opt (
                    keys %{ $r->{'template_sets'}->{$set}->{'options'} } )
                {
                    my $option =
                      $r->{'template_sets'}->{$set}->{'options'}->{$opt};

                    # If the option does not define a tag name,
                    # then there is no need to register one
                    next if ( !defined( $option->{tag} ) );
                    my $tag = $option->{tag};

               # TODO - there is the remote possibility that a template set
               # will attempt to register a duplicate tag. This case needs to be
               # handled properly. Or does it?
               # Note: the tag handler takes into consideration the blog_id, the
               # template set id and the option/setting name.
                    if ( $tag =~ s/\?$// ) {
                        $tags->{block}->{$tag} = sub {
                            $_[0]->stash( 'field',     $set . '_' . $opt );
                            $_[0]->stash( 'plugin_ns', $obj->id );
                            runner( '_hdlr_field_cond',
                                'ConfigAssistant::Plugin', @_ );
                        };
                    }
                    elsif ( $tag ne '' ) {
                        $tags->{function}->{$tag} = sub {
                            $_[0]->stash( 'field',     $set . '_' . $opt );
                            $_[0]->stash( 'plugin_ns', $obj->id );
                            runner( '_hdlr_field_value',
                                'ConfigAssistant::Plugin', @_ );
                        };
                    }
                }
            }
        }
    }

    $tags->{function}{'PluginConfigForm'} =
      '$ConfigAssistant::ConfigAssistant::Plugin::tag_config_form';
    return $tags;
}

sub runner {
    my $method = shift;
    my $class  = shift;
    eval "require $class;";
    if ($@) { die $@; $@ = undef; return 1; }
    my $method_ref = $class->can($method);
    my $plugin     = MT->component("ConfigAssistant");
    return $method_ref->( $plugin, @_ ) if $method_ref;
    die $plugin->translate( "Failed to find [_1]::[_2]", $class, $method );
}

1;
