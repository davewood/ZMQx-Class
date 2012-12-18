use strict;
use warnings;
use 5.010;

use Test::Most;

use ZMQx::Class;
use ZMQ::LibZMQ3;

my $context = zmq_init();

foreach (qw(REQ REP DEALER ROUTER PULL PUSH PUB SUB XPUB XSUB PAIR)) {
    lives_ok {
        ZMQx::Class->socket($context, $_);
    } "could init socket $_";
}

dies_ok { ZMQx::Class->socket($context, "NOSUCHSOCK") }
    "could not init socket NOSUCHSOCK";

lives_ok {
    ZMQx::Class->socket($context, 'PULL', bind=>'tcp://*:5599');
} "init socket & bind";

lives_ok {
    ZMQx::Class->socket($context, 'PULL', connect=>'tcp://*:5599');
} "init socket & bind";

dies_ok {
    ZMQx::Class->socket($context, 'PULL', teleport=>'tcp://*:5599');
} "cannot init socket & teleport";

done_testing();

