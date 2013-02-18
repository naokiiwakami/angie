#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy upgrade support.  In contrast to proxy_websocket.t
# this test doesn't try to use binary WebSocket protocol, but uses simple
# plain text protol instead.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Poll;
use IO::Select;
use IO::Socket::INET;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)
	->write_file_expand('nginx.conf', <<'EOF')->plan(28);

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_read_timeout 2s;
            send_timeout 2s;
        }
    }
}

EOF

$t->run_daemon(\&upgrade_fake_daemon);
$t->run();

###############################################################################

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.3.13');

# establish connection

my $s = upgrade_connect();
ok($s, "handshake");

SKIP: {
	skip "handshake failed", 22 unless $s;

	# send a frame

	upgrade_write($s, 'foo');
	is(upgrade_read($s), 'bar', "upgrade response");

	# send some big frame

	upgrade_write($s, 'foo' x 16384);
	like(upgrade_read($s), qr/^(bar){16384}$/, "upgrade big response");

	# send multiple frames

	for my $i (1 .. 10) {
		upgrade_write($s, ('foo' x 16384) . $i);
		upgrade_write($s, 'bazz' . $i);
	}

	for my $i (1 .. 10) {
		like(upgrade_read($s), qr/^(bar){16384}\d+$/, "upgrade $i");
		is(upgrade_read($s), 'bazz' . $i, "upgrade small $i");
	}
}

# establish connection with some pipelined data
# and make sure they are correctly passed upstream

undef $s;
$s = upgrade_connect(message => "foo");
ok($s, "handshake pipelined");

SKIP: {
	skip "handshake failed", 2 unless $s;

	is(upgrade_read($s), "bar", "response pipelined");

	upgrade_write($s, "foo");
	is(upgrade_read($s), "bar", "next to pipelined");
}

# connection should not be upgraded unless upgrade was actually
# requested and allowed by configuration

undef $s;
$s = upgrade_connect(noheader => 1);
ok($s, "handshake noupgrade");

SKIP: {
	skip "handshake failed", 2 unless $s;

	upgrade_write($s, "foo");
	isnt(upgrade_read($s), "bar", "after handshake noupgrade");
}

}

###############################################################################

sub upgrade_connect {
	my (%opts) = @_;

	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1:8080'
	)
		or die "Can't connect to nginx: $!\n";

	# send request, $h->to_string

	my $buf = "GET / HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. ($opts{noheader} ? '' : "Upgrade: foo" . CRLF)
		. "Connection: Upgade" . CRLF . CRLF;

	$buf .= $opts{message} . CRLF if defined $opts{message};

	local $SIG{PIPE} = 'IGNORE';

	log_out($buf);
	$s->print($buf);

	# read response

	my $got = '';
	$buf = '';

	while (1) {
		$buf = $s->getline();
		last unless length $buf;
		log_in($buf);
		$got .= $buf;
		last if $got =~ /\x0d?\x0a\x0d?\x0a$/;
	}

	# parse server response

	return $s if $got =~ m!HTTP/1.1 101!;
}

sub upgrade_write {
	my ($s, $message) = @_;
	$s->print($message . CRLF);
}

sub upgrade_read {
	my ($s) = @_;
	my $m = $s->getline();
	$m =~ s/\x0d?\x0a// if defined $m;
	return $m;
}

###############################################################################

sub upgrade_fake_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8081',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while (my $client = $server->accept()) {
		upgrade_handle_client($client);
        }
}

sub upgrade_handle_client {
	my ($client) = @_;

	$client->autoflush(1);
	$client->blocking(0);

	my $poll = IO::Poll->new;

	my $handshake = 1;
	my $unfinished = '';
	my $buffer = '';
	my $n;

	log2c("(new connection $client)");

	while (1) {
        	$poll->mask($client => ($buffer ? POLLIN|POLLOUT : POLLIN));
		my $p = $poll->poll(0.5);
		log2c("(poll $p)");

		foreach my $reader ($poll->handles(POLLIN)) {
			$n = $client->sysread(my $chunk, 65536);
			return unless $n;

			log2i($chunk);

			if ($handshake) {
				$buffer .= $chunk;
				next unless $buffer =~ /\x0d?\x0a\x0d?\x0a$/;

				log2c("(handshake done)");

				$handshake = 0;
				$buffer = 'HTTP/1.1 101 Switching' . CRLF
					. 'Upgrade: foo' . CRLF
					. 'Connection: Upgrade' . CRLF . CRLF;

				next;
			}

			$unfinished .= $chunk;

			if ($unfinished =~ m/\x0d?\x0a\z/) {
				$unfinished =~ s/foo/bar/g;
				$buffer .= $unfinished;
				$unfinished = '';
			}
		}

		foreach my $writer ($poll->handles(POLLOUT)) {
			next unless length $buffer;
			$n = $writer->syswrite($buffer);
			substr $buffer, 0, $n, '';
		}
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
