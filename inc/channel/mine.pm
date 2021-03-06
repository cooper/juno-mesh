#!/usr/bin/perl
# Copyright (c) 2010-12, Mitchell Cooper

# this file contains channely stuff for local users
# and even some servery channely stuff.
package channel::mine;

use warnings;
use strict;

use utils qw[log2 conf gv];

# omg hax
# it has the same name as the one in channel.pm.
# the only difference is that this one sends
# the mode changes around
sub cjoin {
    my ($channel, $user, $time, $force) = @_;
    if ($channel->has_user($user)) {
        return unless $force
    }
    else {
        $channel->cjoin($user, $time);
    }

    # for each user in the channel
    foreach my $usr (@{$channel->{users}}) {
        next unless $usr->is_local;
        $usr->sendfrom($user->full, "JOIN $$channel{name}")
    }

    names($channel, $user);
    $user->handle("TOPIC $$channel{name}") if exists $channel->{topic};
    $user->numeric('RPL_ENDOFNAMES', $channel->{name});

    return $channel->{time};
}

# send NAMES
# this is here instead of user::handlers because it is convenient to send on channel join
sub names {
    my ($channel, $user) = @_;
    my @str;
    my $curr = 0;
    foreach my $usr (@{$channel->{users}}) {

        # if this user is invisible, do not show him unless the querier is in a common
        # channel or has the see_invisible flag.
        if ($usr->is_mode('invisible')) {
            next if !$channel->has_user($user) && !$user->has_flag('see_invisible')
        }

        $str[$curr] .= prefix($channel, $usr).$usr->{nick}.q( );
        $curr++ if length $str[$curr] > 500
    }
    $user->numeric('RPL_NAMEREPLY', '=', $channel->{name}, $_) foreach @str
}

sub modes {
    my ($channel, $user) = @_;
    $user->numeric('RPL_CHANNELMODEIS', $channel->{name}, $channel->mode_string($user->{server}));
    $user->numeric('RPL_CREATIONTIME', $channel->{name}, $channel->{time});
}

sub send_all {
    my ($channel, $what, $ignore) = @_;
    foreach my $user (@{$channel->{users}}) {
        next unless $user->is_local;
        next if defined $ignore && $ignore == $user;
        $user->send($what);
    }
    return 1
}

# send a notice to every user
sub notice_all {
    my ($channel, $what, $ignore) = @_;
    foreach my $user (@{$channel->{users}}) {
        next unless $user->is_local;
        next if defined $ignore && $ignore == $user;
        $user->send(":".gv('SERVER', 'name')." NOTICE $$channel{name} :*** $what");
    }
    return 1
}

# send to all members of channels in common
# with a user, but only once.
sub send_all_user {
    my ($user, $what) = @_;
    $user->sendfrom($user->full, $what);
    my %sent = ( $user => 1 );

    foreach my $channel (values %channel::channels) {
        next unless $channel->has_user($user);

        # send to each member
        foreach my $usr (@{$channel->{users}}) {
            next unless $usr->is_local;
            next if $sent{$usr};
            $usr->sendfrom($user->full, $what);
            $sent{$usr} = 1
        }

    }
}

# take the lower time of a channel and unset higher time stuff
sub take_lower_time {
    my ($channel, $time) = @_;
    return $channel->{time} if $time >= $channel->{time}; # never take a time that isn't lower

    log2("locally resetting $$channel{name} time to $time");
    my $amount = $channel->{time} - $time;
    $channel->set_time($time);
    notice_all($channel, "channel TS set back $amount seconds");

    # unset topic
    send_all($channel, ':'.gv('SERVER', 'name')." TOPIC $$channel{name} :");
    delete $channel->{topic};

    # unset all channel modes
    my $modestring = ($channel->mode_string_all(gv('SERVER')))[0];
    $modestring =~ s/\+/\-/;
    send_all($channel, ':'.gv('SERVER', 'name')." MODE $$channel{name} $modestring");
    $channel->{modes} = {};

    notice_all($channel, 'channel properties reset');
    return $channel->{time}
}

# I hate this subroutine.
# returns the highest prefix a user has
sub prefix {
    my ($channel, $user) = @_;
    my $level = $channel->user_get_highest_level($user);
    if (defined $level && $channel::modes::prefixes{$level}) {
        return $channel::modes::prefixes{$level}[1]
    }
    return q..
}

1
