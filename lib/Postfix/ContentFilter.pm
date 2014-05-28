package Postfix::ContentFilter;

use Modern::Perl;
use Carp;
use Try::Tiny 0.11;
use IPC::Open3 1.03;
use Scalar::Util qw(blessed);

=head1 NAME

Postfix::ContentFilter - a perl content_filter for postfix

=head1 VERSION

Version 1.02

=cut

our $VERSION = '1.02';

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

=head1 FUNCTIONS

=head2 new($args)
C<new> creates a new Postfix::Contentfilter. It takes an optional argument of a hash with the key 'parser', which specifies the parser to use as per C<footer>. This can be either C<MIME::Entity> or C<Mail::Message>.

Alternatively C<process> can be called directly.

=cut

sub new($%)
{   my ($class, $options) = @_;
    my $self = bless {}, $class;
    if ($options && $options->{parser})
    {
        parser($self, $options->{parser});
    }

    $self;
}

=head2 parser($string)

C<parser()> specifies the parser to use, which can be either C<MIME::Parser> or C<Mail::Message>. It defaults to C<MIME::Parser>, if available, or C<Mail::Message> whichever could be found first. When called without any arguments, it returns the current parser.

=cut

sub _load_any {
	foreach my $module (@_) {
		my $path = $module;
		$path =~ s/::/\//g;
		$path .= '.pm';
		return $module if exists $INC{$path};
		eval "require $module; 1" and return $module;
	}
    croak("Couldn't find any of these implementations: @_");
}

sub parser {
    my ($self, $ptype) = @_;
	my $parsers = {
		# Key is parser, value is returned entity
		'MIME::Parser'  => 'MIME::Entity',
		'Mail::Message' => 'Mail::Message',
	};
	
	return $self->{parser} if defined $self->{parser} and not defined $ptype;

	$ptype = _load_any($ptype || qw(MIME::Parser Mail::Message));
	
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

=head2 process($coderef [, $inputhandle])

C<process()> reads the mail from C<STDIN> (or C<$inputhandle>, if given), parses it, calls the coderef and finally runs C<sendmail> with our own command-line arguments (C<@ARGV>).

This function returns the exitcode of C<sendmail>.

=cut

sub process($&;*) {
    my ($class, $coderef, $handle) = @_;
    
    my $self = blessed $class
	         ? $class
			 : bless {}, $class
			 ; # For backwards compatibility, to enable calling directly

    confess "please call as ".__PACKAGE__."->process(sub{ ... })" unless ref $coderef eq 'CODE';
    
    $handle = \*STDIN unless ref $handle eq 'GLOB';

    my $entity;
    my $parser = $self->parser;
	
	given (ref $parser || $parser) {
		when ('Mail::Message') {
			$entity = $parser->read($handle) or confess "failed to parse with Mail::Message";
		}
		when ('MIME::Parser') {
			$parser = $parser->new;
			$entity = $parser->parse($handle) or confess "failed to parse wth MIME::Parser";
		}
		default {
			confess "Unkown parser $parser";
		}
	}
	
    try {
		$entity = $coderef->($entity);
    } catch {
		given (ref $parser || $parser) {
			when ('Mail::Message') {
	            $entity->DESTROY;
			}
			when ('MIME::Parser') {
	            $parser->filer->purge;
			}
		}
		confess $_;
    };
    
    confess "subref should return instance of $self->{entity}"
        unless blessed($entity) and $entity->isa($self->{entity});

    my $ret = -1;
    
    $SIG{CHLD} = sub { wait; $ret = $? if $? >= 0 };
    
    delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV', 'PATH'} if ${^TAINT};
    
    my ($in, $out, $err);
    my $pid = open3 ($in, $out, $err, @$sendmail, @ARGV) or confess "open3: $!";
    
    $entity->print($in) or confess "print: $!";

    close $in;
    
    $output = join '' => <$out> if defined $out;
    $error = join '' => <$err> if defined $err;
    
    close $out;
    
    waitpid($pid, 0);
	$ret = $? if $? >= 0;
    
	given (ref $parser || $parser) {
		when ('Mail::Message') {
			$entity->DESTROY;
		}
		when ('MIME::Parser') {
			$parser->filer->purge;
		}
	}
	
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

=head1 AUTHOR

David Zurborg, C<< <zurborg at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests trough L<my project management tool|http://development.david-zurb.org/projects/libpostfix-contentfilter-perl/issues/new>. I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Postfix::ContentFilter

You can also look for information at:

=over 4

=item * Redmine: Homepage of this module

L<http://development.david-zurb.org/projects/libpostfix-contentfilter-perl>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Postfix-ContentFilter>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Postfix-ContentFilter>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Postfix-ContentFilter>

=item * Search CPAN

L<http://search.cpan.org/dist/Postfix-ContentFilter/>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2014 David Zurborg, all rights reserved.

This program is free software; you can redistribute it and/or modify it under the terms of the ISC license.

=cut

1; # End of Postfix::ContentFilter
