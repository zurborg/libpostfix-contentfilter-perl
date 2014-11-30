use strict;
use warnings;
package Postfix::ContentFilter;
# ABSTRACT: a perl content_filter for postfix

use Carp;
use Try::Tiny 0.11;
use Scalar::Util qw(blessed);
use Class::Load qw(load_first_existing_class);
use AnyEvent::Proc;

# VERSION

=head1 SYNOPSIS

    use Postfix::ContentFilter;

    $exitcode = Postfix::ContentFilter->process(sub{
	$entity = shift; # isa MIME::Entity
	
	# do something with $entity
	
	return $entity;
    });
    
    # Or specifying the parser
    my $cf = Postfix::ContentFilter->new({ parser => 'Mail::Message' });

    $exitcode = $cf->process(sub{
	$entity = shift; # isa Mail::Message
	
	# do something with $entity
	
	return $entity;
    });

    exit $exitcode;

=head1 DESCRIPTION

Postfix::ContentFilter can be used for C<content_filter> scripts, as described here: L<http://www.postfix.org/FILTER_README.html>.

=cut

our $parser;
our $sendmail = [qw[ /usr/sbin/sendmail -G -i ]];
our $output;
our $error;

=method new($args)

C<new> creates a new Postfix::Contentfilter. It takes an optional argument of a hash with the key 'parser', which specifies the parser to use as per C<footer>. This can be either C<MIME::Entity> or C<Mail::Message>.

Alternatively C<process> can be called directly.

=cut

sub new {
	my ($class, $options) = @_;
    my $self = bless {}, $class;
    if ($options && $options->{parser}) {
        parser($self, $options->{parser});
    }
    return $self;
}

=method parser($string)

C<parser()> specifies the parser to use, which can be either C<MIME::Parser> or C<Mail::Message>. It defaults to C<MIME::Parser>, if available, or C<Mail::Message> whichever could be found first. When called without any arguments, it returns the current parser.

=cut

sub parser {
    my ($self, $ptype) = @_;
	my $parsers = {
		# Key is parser, value is returned entity
		'MIME::Parser'  => 'MIME::Entity',
		'Mail::Message' => 'Mail::Message',
	};
	
	return $self->{parser} if defined $self->{parser} and not defined $ptype;

	$ptype = load_first_existing_class(map { $_ => {} } ($ptype || qw(MIME::Parser Mail::Message)));
	
	if (my $ent = $parsers->{$ptype}) {
        $self->{parser} = $ptype;
        $self->{entity} = $ent;
    } else {
        croak "Unknown parser $ptype";
    }
	
    return $self->{parser};
}

sub _parse {
	my ($self, $handle) = @_;
}

=method process($coderef [, $inputhandle])

C<process()> reads the mail from C<STDIN> (or C<$inputhandle>, if given), parses it, calls the coderef and finally runs C<sendmail> with our own command-line arguments (C<@ARGV>).

This function returns the exitcode of C<sendmail>.

=cut

sub process {
    my ($class, $coderef, $handle) = @_;
    
    my $self = blessed $class
	         ? $class
			 : bless {}, $class
			 ; # For backwards compatibility, to enable calling directly

    confess "please call as ".__PACKAGE__."->process(sub{ ... })" unless ref $coderef eq 'CODE';
    
    $handle = \*STDIN unless ref $handle eq 'GLOB';

    my $entity;
    my $parser = $self->parser;
    my $module = ref $parser || $parser;
	
    if ($module eq 'Mail::Message') {
        $entity = $parser->read($handle) or confess "failed to parse with Mail::Message";
    } elsif ($module eq 'MIME::Parser') {
        $parser = $parser->new;
        $entity = $parser->parse($handle) or confess "failed to parse wth MIME::Parser";
    } else {
        confess "Unkown parser $parser";
    }
	
    try {
		$entity = $coderef->($entity);
    } catch {
        $module = ref $parser || $parser;
        if ($module eq 'Mail::Message') {
            $entity->DESTROY;
        } elsif ($module eq 'MIME::Parser') {
            $parser->filer->purge;
        }
        confess $_;
    };
    
    confess "subref should return instance of $self->{entity}"
        unless blessed($entity) and $entity->isa($self->{entity});

    my $ret;
    
    delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV', 'PATH'} if ${^TAINT};
    
    $output = undef;
    $error = undef;

	my $in;
	
	try {
    
		my ($bin, @args) = (@$sendmail, @ARGV);
		my $proc = AnyEvent::Proc->new(bin => $bin, args => \@args, ttl => 60, outstr => \$output, errstr => \$error);
		
		my $module = ref $parser || $parser;
		if ($module eq 'Mail::Message') {
			$entity->print($proc->in->fh);
        } elsif ($module eq 'MIME::Parser') {
			$entity->print($proc->in->fh);
		}
		$proc->finish;
		$ret = !$proc->wait;
		
	} catch {

		local $, = ' ';
		confess "error: $_ with @$sendmail @ARGV";

	} finally {

	    my $module = ref $parser || $parser;
		if ($module eq 'Mail::Message') {
            $entity->DESTROY;
        } elsif ($module eq 'MIME::Parser') {
            $parser->filer->purge;
		}

	};
	
    return $ret;
}

=head1 VARIABLES

=over 4

=item * C<$sendmail>

C<$sendmail> defaults to C</usr/sbin/sendmail>.

    $Postfix::ContentFilter::sendmail = [ '/usr/local/sbin/sendmail', '-G', '-i' ];

Please note C<$sendmail> must be an arrayref. Don't forget to use the proper arguments for C<sendmail>, or just replace the first element in array.

Additional arguments can be added with:

    push @$Postfix::ContentFilter::sendmail => '-t';

=item * C<$output>

Any output from C<sendmail> command is populated in C<$output>.

=item * C<$parser>

The L<MIME::Parser|MIME::Parser> object is available via C<$parser>. To tell where to put the things, use:

    $Postfix::ContentFilter::parser->output_under('/tmp');

=back

=head1 CAVEATS

If taint mode is on, %ENV will be stripped:

    delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV', 'PATH'}

So set C<$Postfix::ContentFilter::sendmail> to an absolute path, if you are using taint mode. See L<perlsec(1)|perlsec(1)> for more details about unsafe variables and tainted input.

=head1 SEE ALSO

=over 4

=item * L<MIME::Entity>

=item * L<postconf(5)>

=item * L<postfix(1)>

=back

=cut

1;
