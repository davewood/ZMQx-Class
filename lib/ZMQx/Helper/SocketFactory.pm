package ZMQx::Helper::SocketFactory;
use strict;
use warnings;
use 5.010;
use ZMQx::Helper::Socket;

use ZMQ::LibZMQ3 qw(zmq_socket zmq_init);
use ZMQ::Constants qw(ZMQ_REQ ZMQ_REP ZMQ_DEALER ZMQ_ROUTER ZMQ_PULL ZMQ_PUSH ZMQ_PUB ZMQ_SUB  ZMQ_XPUB ZMQ_XSUB ZMQ_PAIR);

my %types = (
    'REQ'=>ZMQ_REQ,
    'REP'=>ZMQ_REP,
    'DEALER'=>ZMQ_DEALER,
    'ROUTER'=>ZMQ_ROUTER,
    'PULL'=>ZMQ_PULL,
    'PUSH'=>ZMQ_PUSH,
    'PUB'=>ZMQ_PUB,
    'SUB'=>ZMQ_SUB,
    'XPUB'=>ZMQ_XPUB,
    'XSUB'=>ZMQ_XSUB,
    'PAIR'=>ZMQ_PAIR,
);

sub make {
    my ($class, $context, $type, $connect, $address ) = @_;
    die "no such socket type: $type" unless defined $types{$type};
    my $socket = ZMQx::Helper::Socket->new(
        socket=>zmq_socket($context,$types{$type}),
    );
    if ($connect && $address) {
        if ($connect eq 'bind') {
            $socket->bind($address);
        }
        elsif ($connect eq 'connect') {
            $socket->connect($address);
        }
        else {
            die "no such connect type: $connect";
        }
    }
    return $socket;
}

1;
