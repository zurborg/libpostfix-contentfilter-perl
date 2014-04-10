%BuildOptions = (%BuildOptions,
    NAME                => 'Postfix::ContentFilter',
    AUTHOR              => 'David Zurborg <zurborg@cpan.org>',
    VERSION_FROM        => 'lib/Postfix/ContentFilter.pm',
    ABSTRACT_FROM       => 'lib/Postfix/ContentFilter.pm',
    LICENSE             => 'open-source',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist => {
        COMPRESS            => 'gzip -9f',
        SUFFIX              => 'gz',
        CI                  => 'git add',
        RCS_LABEL           => 'true',
    },
    clean               => { FILES => 'Postfix-ContentFilter-* *~' },
    depend => {
	'$(FIRST_MAKEFILE)' => 'BuildOptions.pm',
    },
);
