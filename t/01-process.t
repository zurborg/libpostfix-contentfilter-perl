#!perl -T

use Test::More tests => 4;

use Postfix::ContentFilter;
use MIME::Entity;

pipe (my $R, my $W) or die "pipe: $!";

print $W "Subject: foo\n\nbar\n";
close $W;

@ARGV = ();

$Postfix::ContentFilter::sendmail = [qw[ /bin/cat ]];

is(Postfix::ContentFilter->process (sub {
	my ($entity) = @_;

	is ($entity->head->get('Subject') => "foo\n");
	is_deeply ($entity->body => ["bar\n"]);
	
	$entity->head->set(Subject => 'bar');
	$entity->bodyhandle(MIME::Body::Scalar->new(["foo\n"]));
	
	return $entity;
}, $R) => 0);

is($Postfix::ContentFilter::output, "Subject: bar\n\nfoo\n");
