#!perl
use strict;
use warnings;
use ExtUtils::MakeMaker 6.64;
use Imager::ExtUtils;

my @imagerRequirement = (Imager => '1.013');

WriteMakefile(
	NAME             => 'Imager::File::SIXEL',
	VERSION_FROM     => 'lib/Imager/File/SIXEL.pm',
	ABSTRACT_FROM    => 'lib/Imager/File/SIXEL.pm',
	AUTHOR           => 'davenonymous <dave@davenonymous.com>',
	LICENSE          => 'perl_5',
	MIN_PERL_VERSION => '5.024',
	OBJECT           => 'SIXEL$(OBJ_EXT) sixel_read$(OBJ_EXT) sixel_write$(OBJ_EXT) sixel_quant$(OBJ_EXT)',
	INC              => Imager::ExtUtils->includes,
	TYPEMAPS         => [Imager::ExtUtils->typemap],
	CONFIGURE_REQUIRES => {
		'ExtUtils::MakeMaker' => '6.64',
		@imagerRequirement,
	},
	PREREQ_PM => {
		@imagerRequirement,
		'Scalar::Util' => 0,
		XSLoader       => 0,
	},
	TEST_REQUIRES => {
		'Test2::V0' => '0.000060',
	},
	clean      => { FILES => 'testout' },
	META_MERGE => {
		'meta-spec' => { version => 2 },
		prereqs     => {
			develop => {
				requires => { 'Test::Pod' => '1.00' },
			},
		},
	},
);
