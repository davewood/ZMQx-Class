use strict;
use warnings;
use 5.014;

use Test::Most;
use ZMQx::RPC::Message::Request;
use ZMQx::RPC::Message::Response;
use ZMQx::Class;
use AnyEvent;
use Data::Dumper;
use ZMQ::Constants qw(ZMQ_DONTWAIT);

package TestLoop;
use Moose;
use JSON::XS;
with 'ZMQx::RPC::Loop' => {
    commands=>[
        'echo',
        'echo_ref',
        'something_raw' => { payload => 'raw' } ,
        'post',
    ]
};
use Test::More;

sub something_raw {
    my ($self, $req ) = @_;
    return ZMQx::RPC::Message::Response->new(status=>200,payload=>['a raw '.$req->command
    # TODO add the string of raw json from the request
    # $req->raw_payload to be implemented;
    ]);
}

sub echo {
    my ($self, @payload ) = @_;
    return map { uc($_),lc($_) } @payload;
}

sub echo_ref {
    my ($self, @payload ) = @_;
    my @new;
    foreach (@payload) {
        my %new;
        while (my ($key,$val) = each %$_) {
            $new{$key} = uc($val);
        }
        push(@new,\%new);
    }
    return @new;
}

my $post = AnyEvent->condvar;

sub post {
    my ($self, @payload ) = @_;
    state $s = 0;
    my $res = ZMQx::RPC::Message::Response->new(
        status=>200
    );
    if (@payload) {
        $res->post_send(sub {
            my ($req, $res) = @_;
            isa_ok($req, 'ZMQx::RPC::Message::Request', 'callback first arg');
            isa_ok($res, 'ZMQx::RPC::Message::Response', 'callback second arg');
            $s = $payload[0];
            $post->send('Hello from the callback', $payload[1]);
        });
    }
    $res->payload([$s]);
    ++$s;

    return $res;
}

package main;

my $context = ZMQx::Class->context;
my $port = int(rand(64)+1).'025';
my $endpoint = "ipc:///tmp/test-zmqx-class-$$:".$port;

diag("running zmq on $endpoint");

my $server = ZMQx::Class->socket($context, 'REP', bind =>$endpoint );
my $client = ZMQx::Class->socket($context, 'REQ', connect =>$endpoint);

my $rpc = TestLoop->new;

my $stop = AnyEvent->timer(
    after=>5,
    cb=>sub {
        diag "killed server and tests after 5 secs";
        $rpc->_server_is_running(0);
    }
);

my @tests =
    (
     "echo" => sub {
         my $done = shift;
         my $msg = ZMQx::RPC::Message::Request->new(command=>'echo');
         my $c = AnyEvent->io(
                              fh   => $client->get_fd,
                              poll => "r",
                              cb   =>             sub {
                                  my $raw = $client->receive_bytes(1);
                                  my $res = ZMQx::RPC::Message::Response->unpack($raw);
                                  is($res->status,200,'status: 200');
                                  is($res->header->type,'string','header->type');
                                  is($res->payload->[0],'HELLO WORLD','payload string uppercase');
                                  is($res->payload->[1],'hello world','payload string lowercase');
                                  $done->send();
                              });
         $client->send_bytes($msg->pack('hello world'));
         return $c;
     },
     "echo_ref" => sub {
         my $done = shift;
         my $msg = ZMQx::RPC::Message::Request->new(
                                                    command=>'echo_ref',
                                                    header=>ZMQx::RPC::Header->new(type=>'JSON'),
                                                   );
         my $c = AnyEvent->io(
                              fh   => $client->get_fd,
                              poll => "r",
                              cb   =>             sub {
                                  my $raw = $client->receive_bytes(1);
                                  my $res = ZMQx::RPC::Message::Response->unpack($raw);
                                  is($res->status,200,'status: 200');
                                  is($res->header->type,'JSON','header->type');
                                  is($res->payload->[0]{foo},'BAR','payload JSON uppercase');
                                  is($res->payload->[1]{foo},42,'payload JSON uppercase');
                                  $done->send();
                              });
         $client->send_bytes($msg->pack({foo=>'bar'},{foo=>42}));
         return $c;
     },
     "something_raw" => sub {
         my $done = shift;
         my $msg = ZMQx::RPC::Message::Request->new(
                                                    command=>'something_raw',
                                                    header=>ZMQx::RPC::Header->new(type=>'JSON'),
                                                   );
         my $c = AnyEvent->io(
                              fh   => $client->get_fd,
                              poll => "r",
                              cb   =>             sub {
                                  my $raw = $client->receive_bytes(1);
                                  my $res = ZMQx::RPC::Message::Response->unpack($raw);
                                  is($res->status,200,'status: 200');
                                  is($res->header->type,'string','header->type');
                                  is($res->payload->[0],'a raw something_raw','payload raw');
                                  # is($res->payload->[1],'stringifyed json','payload JSON lowercase');
                                  $done->send();
                              });
         $client->send_bytes($msg->pack({foo=>'bar'},{foo=>42}));
         return $c;
     },
     "post" => sub {
         my $done = shift;
         my $msg = ZMQx::RPC::Message::Request->new(
                                                    command=>'post',
                                                   );
         my $c = AnyEvent->io(
                              fh   => $client->get_fd,
                              poll => "r",
                              cb   =>             sub {
                                  my $raw = $client->receive_bytes(1);
                                  my $res = ZMQx::RPC::Message::Response->unpack($raw);
                                  is($res->status,200,'status: 200');
                                  is($res->header->type,'string','header->type');
                                  is($res->payload->[0], 0, 'Got 0');
                                  ok(!$post->ready(), 'Callback not called yet');
                                  $done->send();
                              });
         $client->send_bytes($msg->pack());
         return $c;
     },
     "post 2" => sub {
         my $done = shift;
         my $msg = ZMQx::RPC::Message::Request->new(
                                                    command=>'post',
                                                   );
         ok(!$post->ready(), 'Callback not called yet');
         my $c = AnyEvent->io(
                              fh   => $client->get_fd,
                              poll => "r",
                              cb   =>             sub {
                                  my $raw = $client->receive_bytes(1);
                                  my $res = ZMQx::RPC::Message::Response->unpack($raw);
                                  is($res->status,200,'status: 200');
                                  is($res->header->type,'string','header->type');
                                  is($res->payload->[0], 1, 'Got 1');
                                  $done->send();
                              });
         $client->send_bytes($msg->pack('Hello', 'World'));
         # At some point after here the callback is called.
         return $c;
     },
     "post 3" => sub {
         my $done = shift;
         my $msg = ZMQx::RPC::Message::Request->new(
                                                    command=>'post',
                                                   );
         ok($post->ready(), 'Callback has been called');
         my @got = $post->recv();
         is_deeply(\@got,
                   ['Hello from the callback',
                    'World',
                   ], 'Callback results');
         my $c = AnyEvent->io(
                              fh   => $client->get_fd,
                              poll => "r",
                              cb   =>             sub {
                                  my $raw = $client->receive_bytes(1);
                                  my $res = ZMQx::RPC::Message::Response->unpack($raw);
                                  is($res->status,200,'status: 200');
                                  is($res->header->type,'string','header->type');
                                  is($res->payload->[0], 'Hello', 'Got Hello');
                                  $done->send();
                              });
         $client->send_bytes($msg->pack());
         return $c;
     },
    );


{
    # This variable feels ugly, but the way things are structured, we
    # need a way to keep condition variables around until the entire
    # test is done.
    my @state;
    my $done;
    sub launch_next_test {
        unless (@tests) {
            diag "Out of tests, so terminating server";
            $rpc->_server_is_running(0);
            # We're done.
            return;
        }
        undef @state;
        my ($desc, $next_test) = splice @tests, 0, 2;
        note "Starting subtest $desc";
        $done = AnyEvent->condvar();
        $done->cb(\&launch_next_test);
        @state = $next_test->($done);
    };
}

# Serve up the first test:
launch_next_test();

$rpc->loop($server, $client);

done_testing();
