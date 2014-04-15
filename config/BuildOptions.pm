%BuildOptions = (%BuildOptions,
    NAME                => 'Postfix::ContentFilter',
    AUTHOR              => 'David Zurborg <zurborg@cpan.org>',
    VERSION_FROM        => 'lib/Postfix/ContentFilter.pm',
    ABSTRACT_FROM       => 'lib/Postfix/ContentFilter.pm',
    LICENSE             => 'open-source',
    PL_FILES            => {},
    PMLIBDIRS           => [qw[ lib ]],
    PREREQ_PM => {
        'Test::More'        => 0,
	'MIME::Parser'      => 5.503,
	'Try::Tiny'         => 0.11,
	'IPC::Open2'        => 1.03,
    },
    dist => {
        COMPRESS            => 'gzip -9f',
        SUFFIX              => 'gz',
        CI                  => 'git add',
        RCS_LABEL           => 'true',
    },
    clean               => { FILES => 'Postfix-ContentFilter-* *~' },
    depend => {
	'$(FIRST_MAKEFILE)' => 'config/BuildOptions.pm',
    },
);
