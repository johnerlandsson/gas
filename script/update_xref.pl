#!/usr/bin/perl -w

use 5.18.4;

use Parse::GEDA::Gschem;
use Data::Dumper;
no warnings 'experimental::smartmatch';

$Parse::GEDA::Gschem::ERRORFILENAME = 'error.log';

# ========================================================================================================
# map_titleblock
# map XY cordinates to titleblock
# ========================================================================================================
sub map_titleblock
{
	my $x = $_[0];
	my $y = $_[1];
	my $ret_x = "";
	my $ret_y = "";

	if( $x ge 40200 and $x le 42000 )
	{
		$ret_x = '1';
	}
	elsif( $x gt 42000 and $x le 43900 )
	{
		$ret_x = '2';
	}
	elsif( $x gt 43900 and $x le 45900 )
	{
		$ret_x = '3';
	}
	elsif( $x gt 45900 and $x le 47900 )
	{
		$ret_x = '4';
	}
	elsif( $x gt 47900 and $x le 49800 )
	{
		$ret_x = '5';
	}
	elsif( $x gt 49800 and $x le 51400 )
	{
		$ret_x = '6';
	}
	else
	{
		$ret_x = 'invalid_x';
	}


	if( $y ge 40200 and $y le 42000 )
	{
		$ret_y = 'A';
	}
	elsif( $y ge 42000 and $y le 43900 )
	{
		$ret_y = 'B';
	}
	elsif( $y ge 43900 and $y le 45900 )
	{
		$ret_y = 'C';
	}
	elsif( $y ge 45900 and $y le 47900 )
	{
		$ret_y = 'D';
	}
	elsif( $y ge 47900 and $y le 48000 )
	{
		$ret_y = 'E';
	}
	else
	{
		$ret_y = 'invalid_y';
	}

	return $ret_y . $ret_x;
}

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
		for( my $object_idx = 0; $object_idx < @{$files[$file_idx]->{objects}}; $object_idx++ )
		{
			next if( !($files[$file_idx]->{objects}->[$object_idx]->{type} eq 'C') );
			my $refdes_idx = -1;
			my $refdes_value = "";
			my $xref_idx = -1;
			my $xref_value = $_[0] + 1 . '-' . map_titleblock( $_[3], $_[4] );

			for( my $attr_idx = 0; $attr_idx < @{$files[$file_idx]->{objects}->[$object_idx]->{Attributes}}; $attr_idx++ )
			{
				given( $files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{name} )
				{
					when( 'refdes' )
					{
						$refdes_value = $files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{value};
						$refdes_idx = $attr_idx;
					}

					when( 'xref' )
					{
						$xref_idx = $attr_idx;
					}
				}
			}

			# found matching refdes in different component
			if( $refdes_idx ge 0 and !($_[0] eq $file_idx and $_[1] eq $object_idx) )
			{
				if( $refdes_value eq $_[2] )
				{
					if( $xref_idx ge 0 )
					{
						$files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$xref_idx]->{value} = $xref_value;
					}
					else
					{
						print "Found symbol without xref attribute";
					}
				}
			}
		}
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
					# ignore refdes containing questionmarks
					if( $files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{value} !~ /\?/ )
					{
						$refdes = $files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{value};
					}
				}
			}
		}
		
		# update xref if component has xref_master attribute
		if( $xref_master eq '1' and $refdes ne '' )
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
Parse::GEDA::Gschem::writeSchFiles( \@files );
print "Done...\n";
