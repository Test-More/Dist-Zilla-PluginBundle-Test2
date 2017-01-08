package Dist::Zilla::Plugin::Test2::TidyAll;

use v5.10;

use strict;
use warnings;
use autodie;
use namespace::autoclean;

our $VERSION = '0.79';

use Code::TidyAll::Config::INI::Reader 0.44;
use List::Util 1.45 qw( uniqstr );
use Path::Class qw( file );
use Path::Iterator::Rule;
use Perl::Critic::Moose 1.05;
use Sort::ByExample qw( sbe );

use Moose;

with qw(
    Dist::Zilla::Role::BeforeBuild
    Dist::Zilla::Role::TextTemplate
);

my $perltidyrc = <<'EOF';
--indent-columns=4               # size of indentation
--nt                             # no tabs
--entab-leading-whitespace=4     # 4 spaces to a tab when converting to tabs
--continuation-indentation=4     # indentation of wrapped lines
--maximum-line-length=0          # max line length before wrapping (turn it off)
--nooutdent-long-quotes          # do not outdent overly long quotes
--paren-tightness=2              # no spacing for parentheses
--square-bracket-tightness=2     # no spacing for square brackets
--brace-tightness=2              # no spacing for hash curly braces
--block-brace-tightness=0        # spacing for coderef curly braces
--comma-arrow-breakpoints=1      # break long key/value pair lists
--break-at-old-comma-breakpoints # this attempts to retain list break points
--no-blanks-before-comments      # do not insert blank lines before comments
--indent-spaced-block-comments   # no blanks before comments
--nocuddled-else                 # Do not cuddle else
--nospace-for-semicolon          # no space before semicolons in loops
--nospace-terminal-semicolon     # no space before termonal semicolons
--notrim-qw                      # Do not mess with qw{} whitespace
EOF

sub before_build {
	my $self = shift;

	file('tidyall.ini')->spew($self->_tidyall_ini_content);

	$self->_maybe_write_file('perltidyrc', $perltidyrc);

	return;
}

sub _tidyall_ini_content {
	my $self = shift;

	return $self->_new_tidyall_ini
		unless -e 'tidyall.ini';

	return $self->_munged_tidyall_ini;
}

sub _new_tidyall_ini {
	my $self = shift;

	my $perl_select = '**/*.{pl,pm,t,psgi}';
	my %tidyall     = (
		'PerlTidy' => {
			select => [$perl_select],
			ignore => [$self->_default_perl_ignore],
		},
		'Test::Vars' => {
			select => ['**/*.pm'],
			ignore => [$self->_default_perl_ignore],
		},
	);

	return $self->_config_to_ini(\%tidyall);
}

sub _munged_tidyall_ini {
	my $self = shift;

	my $tidyall = Code::TidyAll::Config::INI::Reader->read_file('tidyall.ini');

	my %has_default_ignore = map { $_ => 1 } qw( PerlTidy Test::Vars );
	for my $section (grep { $has_default_ignore{$_} } sort keys %{$tidyall}) {
		$tidyall->{$section}{ignore} = [
			uniqstr(
				@{$tidyall->{$section}{ignore}},
				$self->_default_perl_ignore,
			)
		];
	}

	return $self->_config_to_ini($tidyall);
}

sub _default_perl_ignore {
	my $self = shift;

	my @ignore = qw(
        .build/**/*
        blib/**/*
        t/00-*
        t/author-*
        t/release-*
        t/zzz-*
        xt/**/*
    );

	my $dist = $self->zilla->name;
	push @ignore, "$dist-*/**/*";

	return @ignore;
}

sub _config_to_ini {
	my $self    = shift;
	my $tidyall = shift;

	my @xt_files = Path::Iterator::Rule->new->file->name(qr/\.t$/)->all('xt');

	if (@xt_files) {
		my $suffix = 'non-auto-generated xt';
		for my $plugin (qw( PerlTidy )) {
			$tidyall->{$plugin . q{ } . $suffix}{select} = \@xt_files;
		}
	}

	for my $section (keys %{$tidyall}) {
		if ($section =~ /PerlTidy/) {
			$tidyall->{$section}{argv} = '--profile=$ROOT/perltidyrc';
		}
	}

	my $sorter = sbe(
		['select', 'ignore'],
		{
			fallback => sub { $_[0] cmp $_[1] },
		},
	);

	my $ini = q{};
	for my $section (sort keys %{$tidyall}) {
		$ini .= "[$section]\n";

		for my $key ($sorter->(keys %{$tidyall->{$section}})) {
			for my $val (
				sort ref $tidyall->{$section}{$key}
				? @{$tidyall->{$section}{$key}}
				: $tidyall->{$section}{$key}
				)
			{

				$ini .= "$key = $val\n";
			}
		}

		$ini .= "\n";
	}

	chomp $ini;

	return $ini;
}

sub _maybe_write_file {
	my $self    = shift;
	my $file    = shift;
	my $content = shift;

	return if -e $file;

	file($file)->spew($content);

	return;
}

__PACKAGE__->meta->make_immutable;

1;

# ABSTRACT: Creates default tidyall.ini, and perltidyrc files if they don't yet exist

__END__

=for Pod::Coverage .*
