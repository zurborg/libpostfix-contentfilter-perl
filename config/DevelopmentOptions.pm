addopt(
    postamble => {
        REDMINE_BASEURL     => 'http://development.david-zurb.org/',
        REDMINE_PROJECT     => 'libpostfix-contentfilter-perl',
	README_SECTIONS     => [ 'NAME', 'VERSION', 'DESCRIPTION', 'AUTHOR', 'SUPPORT', 'COPYRIGHT & LICENSE' ],
    },
    depend => {
	'$(FIRST_MAKEFILE)' => 'config/BuildOptions.pm config/DevelopmentOptions.pm',
    },
#   (MM->can('signature_target') ? (SIGN => 1) : ()),
);

sub extend_makefile {
	
	my $out;
	
	while (@_) {
		my $target = shift;
		$out .= "$target :: ";
		my %opts = %{ shift() };
		if (exists $opts{preq}) {
			$out .= join ' ' => @{ $opts{preq} };
		}
		$out .= "\n";
		if (exists $opts{cmds}) {
			$out .= join "\n" => map { "\t$_" } @{ $opts{cmds} };
		}
		$out .= "\n\n";
	}
	
	return $out;
}

sub MY::postamble {
	my ($MM, %options) = @_;
	my @DH_MAKE_PERL_OPTS = (
		'--pkg-perl',
		'--requiredeps',
		(exists $options{DEBIAN_ARCH}                ? ('--arch'      => $options{DEBIAN_ARCH}               ) : ()),
		(exists $options{DEBIAN_BUILD_DEPENDS}       ? ('--bdepends'  => $options{DEBIAN_BUILD_DEPENDS}      ) : ()),
		(exists $options{DEBIAN_BUILD_DEPENDS_INDEP} ? ('--bdependsi' => $options{DEBIAN_BUILD_DEPENDS_INDEP}) : ()),
		(exists $options{DEBIAN_DEPENDS}             ? ('--depends'   => $options{DEBIAN_DEPENDS}            ) : ()),
		(exists $options{DEBIAN_DIST}                ? ('--dist'      => $options{DEBIAN_DIST}               ) : ()),
	);
	return main::extend_makefile(
		redmine_wiki => {
			preq => [qw[ $(MAN1PODS) $(MAN3PODS) ]],
			cmds => [
				sprintf 'pods2redmine --base-url "%s" --project "%s" --version "%s" --with-toc -- $?'
				,$options{REDMINE_BASEURL}
				,$options{REDMINE_PROJECT}
				,$MM->{VERSION}
			]
		},
		'documentation/README.pod' => {
			preq => [ $MM->{ABSTRACT_FROM} ],
			cmds => [
				'podselect '.join(' ' => map { "-section '$_'" } @{ $options{README_SECTIONS} }).' -- "$<" > "$@"'
			]
		},
		README => {
			preq => [qw[ documentation/README.pod ]],
			cmds => [
				'pod2readme "$<" "$@" README'
			]
		},
		'README.md' => {
			preq => [qw[ documentation/README.pod ]],
			cmds => [
				'pod2markdown "$<" "$@"'
			]
		},
		INSTALL => {
			preq => [qw[ documentation/INSTALL.pod ]],
			cmds => [
				'pod2readme "$<" "$@" README'
			]
		},
		documentation => {
			preq => [qw[ README README.md INSTALL ]],
		},
		'all' => {
			preq => [qw[ documentation MANIFEST.SKIP ]]
		},
		'MANIFEST.SKIP' => {
			preq => [qw[ MANIFEST.IGNORE ]],
			cmds => [
			    'echo "#!include_default" > "$@" ',
			    'for file in $?; do echo "#!include $$file" >> "$@"; done',
			    '$(MAKE) skipcheck',
			]
		},
		'debinit' => {
			preq => [ 'distdir' ],
			cmds => [
				'test ! -d debian',
				'(cd $(DISTVNAME) && dh-make-perl '.join(' ', @DH_MAKE_PERL_OPTS).' --version $(VERSION) .)',
				'mv $(DISTVNAME)/debian ./debian',
				'mv $(DISTVNAME)/.git ./debian/git',
				'GIT_DIR=debian/git git config remote.origin.url > debian/git-remote-origin-url',
				'rm -rf $(DISTVNAME)',
				'echo debian/git/ >> .gitignore',
				'git add debian .gitignore',
			]
		},
		'deb' => {
			preq => [ 'distdir' ],
			cmds => [
				'test -d debian/git || git clone --bare `cat debian/git-remote-origin-url` debian/git',
				'rsync -a debian/git/ $(DISTVNAME)/.git/',
				'(cd $(DISTVNAME) && git stash && git checkout upstream && ((git stash pop && git add -A && git commit -m "Release $(DISTNAME) $(VERSION)" && git tag upstream/$(VERSION)) || echo "first release?") && git checkout master && git merge -m "Merge upstream branch for release $(VERSION)" --commit upstream)',
				'rsync -a debian/ $(DISTVNAME)/debian/ --exclude git',
				'rm $(DISTVNAME)/debian/git-remote-origin-url',
				'(cd $(DISTVNAME) && echo dh-make-perl refresh)',
				'fakeroot make -C $(DISTVNAME) -f debian/rules clean',
				         'make -C $(DISTVNAME) -f debian/rules build',
				'fakeroot make -C $(DISTVNAME) -f debian/rules binary',
				'(cd $(DISTVNAME) && dh clean && git add -A)',
			]
		}
	);
}
