#!/usr/bin/perl -w

use 5.18.4;

use Parse::GEDA::Gschem;
use Data::Dumper;
no warnings 'experimental::smartmatch';

$Parse::GEDA::Gschem::ERRORFILENAME = 'test.log';


# Get names of all sch files in current dir
my @schFiles = <*.sch>;

# Parse sch files
our @files = @{Parse::GEDA::Gschem::readSchFiles( \@schFiles )};

# ========================================================================================================
# update_xref
# iterate all objects in all files and update xref attribute of components with matching refdes
# ========================================================================================================
sub update_xref
{
	for( my $file_idx = 0; $file_idx < @files; $file_idx++ )
	{
		print "sub " . $files[$file_idx]->{fileName} . "\n";	
	}
}


# ========================================================================================================
# main program
# ========================================================================================================


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
		
		my $xref_master = "";
		my $refdes = "";
		
		# iterate attributes
		for( my $attr_idx = 0; $attr_idx < @{$files[$file_idx]->{objects}->[$object_idx]->{Attributes}}; $attr_idx++ )
		{
			given( $files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{name} )
			{
				when( 'xref_master' )
				{
					$xref_master = $files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{value};
				}
				when( 'refdes' )
				{
					$refdes = $files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{value};
				}
			}
		}
		
		if( $xref_master eq '1' && $refdes ne '' )
		{
			next if( !($files[$file_idx]->{objects}->[$object_idx]->{x}) );
			next if( !($files[$file_idx]->{objects}->[$object_idx]->{y}) );
			
			my $x = $files[$file_idx]->{objects}->[$object_idx]->{x};
			my $y = $files[$file_idx]->{objects}->[$object_idx]->{y};
			
			print "Found valid component " . $refdes . " with attribute xref_master=1 in " . $files[$file_idx]->{fileName} . " at X" . $x . "Y" . $y . "\n";
			
			update_xref( $file_idx, $object_idx, $refdes, $x, $y );
		}
		
	}
}

# Write changes to sch files
#Parse::GEDA::Gschem::writeSchFiles( \@files );
print "Done...\n";