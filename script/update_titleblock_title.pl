#!/usr/bin/perl -w

use 5.18.4;

use Parse::GEDA::Gschem;
use Data::Dumper;

$Parse::GEDA::Gschem::ERRORFILENAME = 'error.log';

no warnings 'experimental::smartmatch';

#Make sure we passed a title as argument
if( @ARGV == 0 )
{
	print "No title argument.\n";
	exit;
}

my $title = $ARGV[0];

# Get names of all sch files in current dir
my @schFiles = <*.sch>;

# Parse sch files
my @files = @{Parse::GEDA::Gschem::readSchFiles( \@schFiles )};

# iterate files
for( my $file_idx = 0; $file_idx < @files; $file_idx++ )
{
	# next if file has objects in it
	next if( !($files[$file_idx]->{objects}) );
	
	# iterate objects
	for( my $object_idx = 0; $object_idx < @{$files[$file_idx]->{objects}}; $object_idx++ )
	{
		# next if object is a component
		next if( !($files[$file_idx]->{objects}->[$object_idx]->{type} eq 'C') );
		
		# next if it is our titleblock
		next if( !($files[$file_idx]->{objects}->[$object_idx]->{basename} eq 'luna-title-A4.sym') );
		
		print "Found titleblock in: " . $files[$file_idx]->{fileName} . "\n";
		
		# iterate attributes
		for( my $attr_idx = 0; $attr_idx < @{$files[$file_idx]->{objects}->[$object_idx]->{Attributes}}; $attr_idx++ )
		{
			next if( !($files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{name} eq 'title') );
			$files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{value} = $title;
		}
		
	}
}

# Write changes to sch files
Parse::GEDA::Gschem::writeSchFiles( \@files );
print "Done...\n";
