#!/usr/bin/perl -w

# Copyright (C) 2014 John Erlandsson
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

use 5.18.4;

use Parse::GEDA::Gschem;
use Data::Dumper;
no warnings 'experimental::smartmatch';

$Parse::GEDA::Gschem::ERRORFILENAME = 'error.log';

# ========================================================================================================
# usage
# ========================================================================================================
# Print usage information
sub usage
{
	print "Usage $0 [-htx]";
	print "\n";
	print "-b -bck\t\tCreate backup before performing actions.\n";
	print "-h -help\t\tDisplay this help.\n";
	print "-x -xref\t\tUpdate crossreferences on all schematics in folder.\n";
	print "-t -title [TITLE]\tSets the title attribute on titleblocks.\n";
	print "-p -pages\t\tUpdates the page number part of titleblocks.\n";
	print "\n";
}

# ========================================================================================================
# chk_args
# ========================================================================================================
# Handle command line arguments
sub chk_args
{
	our @ARGV;
	our $do_backup;
	our $do_xref;
	our $do_title;
	our $titleblock_title;
	our $do_pages;
	
	my $args = { do_backup => 0, do_xref => 0, do_title => 0, titleblock_title => "", do_pages => 0 };

	# iterate arguments
	for( my $arg_idx = 0; $arg_idx < @ARGV; $arg_idx++ )
	{
		if( $ARGV[$arg_idx] =~ /^-x(ref)?$/ )
		{
			$args->{do_xref} = 1;
			$do_xref = 1;
		}
		elsif( $ARGV[$arg_idx] =~ /^-t(itle)?$/ )
		{
			die "No title given..." unless $arg_idx lt (@ARGV - 1);
			$args->{do_title} = 1;
			$do_title = 1;
			$arg_idx++;
			$titleblock_title = $ARGV[$arg_idx];
			$args->{titleblock_title} = $ARGV[$arg_idx];
		}
		elsif( $ARGV[$arg_idx] =~ /^-b(ck)?$/ )
		{
			$do_backup = 1;
			$args->{do_backup} = 1;
		}
		elsif( $ARGV[$arg_idx] =~ /^-p(ages)?$/ )
		{
			$do_pages = 1;
			$args->{do_pages} = 1;
		}
		elsif( $ARGV[$arg_idx] =~ /^-h(elp)?$/ )
		{
			usage();
		}
		else
		{
			usage();
			die "Unknown argument: " . $ARGV[$arg_idx];
		}
	}

	return $args;
}

# ========================================================================================================
# map_titleblock
# ========================================================================================================
# map XY cordinates to titleblock
# used by update_xref
#
#
sub map_titleblock
{
	die "Too many arguments to map_titleblock" unless @_ <= 2;
	die "Too few arguments to map_titleblock" unless @_ >= 2;

	my $x = $_[0];
	my $y = $_[1];
	my $ret_x = "";
	my $ret_y = "";

	# map X coordinate to number
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
		die "map_titleblock: invalid X coordinate";
	}


	# map Y coordinate to number
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
		die "map_titleblock: invalid Y coordinate";
	}

	return $ret_y . $ret_x;
}

# ========================================================================================================
# object_center
# ========================================================================================================
# Returns centerpoint of object
# TODO Find a way of getting component dimensions
#
sub object_center
{
	die "object_center: Takes exactly one argument" unless @_ eq 1;
	my $object = shift;

	my $ret = { x => $object->{x}, y => $object->{y} };

	return $ret;
}

# ========================================================================================================
# hlp_update_xref
# ========================================================================================================
# Helper function for update_xref
# Reiterates all files and components looking for the refdes that was found by update_xref
# then updates or adds the xref attribute with coordinates mapped to the titleblock
#
sub hlp_update_xref
{
	die "Too many arguments to update_xref" unless @_ <= 5;
	die "Too few arguments to update_xref" unless @_ >= 5;

	my $b_file_idx = $_[0];
	my $b_object_idx = $_[1];
	my $b_refdes = $_[2];
	my $b_x = $_[3];
	my $b_y = $_[4];

	our @files;

	# iterate files
	for( my $file_idx = 0; $file_idx < @files; $file_idx++ )
	{
		# iterate objects
		for( my $object_idx = 0; $object_idx < @{$files[$file_idx]->{objects}}; $object_idx++ )
		{
			next if( !($files[$file_idx]->{objects}->[$object_idx]->{type} eq 'C') );
			my $refdes_idx = -1;
			my $refdes_value = "";
			my $xref_idx = -1;
			my $xref_value = $_[0] + 1 . '-' . map_titleblock( $b_x, $b_y );

			# iterate attributes
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
			if( $refdes_idx ge 0 and !($b_file_idx eq $file_idx and $b_object_idx eq $object_idx) )
			{
				if( $refdes_value eq $b_refdes )
				{
					#Update existing xref attribute if exsists
					if( $xref_idx ge 0 )
					{
						$files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$xref_idx]->{value} = $xref_value;
					}
					#Otherwise create new xref attribute
					else
					{
						# place the xref attribute on components origin
						my %new_attr = (
								alignment => '0',
								show_name_value => '1',
								value => $xref_value,
								angle => '0',
								x => $files[$file_idx]->{objects}->[$object_idx]->{x},
								size => '6',
								y => $files[$file_idx]->{objects}->[$object_idx]->{y},
								color => '5',
								name => 'xref',
								type => 'T',
								num_lines => '1',
								visibility => '1'
							       );

						print "Adding new xref attribute to " . $refdes_value . " on page " . ($file_idx + 1) . "\n";
						push( $files[$file_idx]->{objects}->[$object_idx]->{Attributes}, \%new_attr );
					}
				}
			}
		}
	}
}

# ========================================================================================================
# update_xref
# ========================================================================================================
# This subroutine locates symbols with the attribute xref_master=1
# Then locates all symbols with the same refdes and updates the xref attribute with the position of
# master object
#
sub update_xref
{
	our @files;

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
				next unless $files[$file_idx]->{objects}->[$object_idx]->{x};
				next unless $files[$file_idx]->{objects}->[$object_idx]->{y};
				
				my $cords = object_center( $files[$file_idx]->{objects}->[$object_idx] );
				
				print "Found valid component " . $refdes . " with attribute xref_master=1 in " . $files[$file_idx]->{fileName} . " at X" . $cords->{x} . "Y" . $cords->{y} . "\n";
				
				hlp_update_xref( $file_idx, $object_idx, $refdes, $cords->{x}, $cords->{y} );
			}
			
		}
	}
}

# ========================================================================================================
# update_titleblock
# ========================================================================================================
# Locates the titleblock and updates the title, pages or name attributes to the name given with
# command line argument
#
sub update_titleblock
{
	die "update_titleblock requires exactly one argument" unless @_ eq 1;

	my $args = $_[0];
	our @files;

	# iterate files
	for( my $file_idx = 0; $file_idx < @files; $file_idx++ )
	{
		# next if file has objects in it
		next unless $files[$file_idx]->{objects};
		
		# iterate objects
		for( my $object_idx = 0; $object_idx < @{$files[$file_idx]->{objects}}; $object_idx++ )
		{
			# next if object is a component
			next unless $files[$file_idx]->{objects}->[$object_idx]->{type} eq 'C';
			
			# next if it is our titleblock
			next unless ($files[$file_idx]->{objects}->[$object_idx]->{basename} eq 'title-A4.sym' or 
				     $files[$file_idx]->{objects}->[$object_idx]->{basename} eq 'title-A3.sym');
			
			print "Found titleblock in: " . $files[$file_idx]->{fileName} . "\n";
			
			# iterate attributes
			for( my $attr_idx = 0; $attr_idx < @{$files[$file_idx]->{objects}->[$object_idx]->{Attributes}}; $attr_idx++ )
			{
				given( $files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{name} )
				{
					if( $args->{do_title} )
					{
						$files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{value} = $args->{titleblock_title} when 'title';
					}
					if( $args->{do_pages} )
					{
						$files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{value} = @files when 'npages';
						$files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{value} = ($file_idx + 1) when 'page';
					}
				}
			}
			
		}
	}
}

# ========================================================================================================
# main program
# ========================================================================================================
#

our @files;
my $args = chk_args();

# Get names of all sch files in current dir
my @schFiles = <*.sch>;

# back up schematic files
if( $args->{do_backup} )
{
	print "Creating backup...\n";
	Parse::GEDA::Gschem::bakSchFiles( \@schFiles );
}

if( $args->{do_xref} or $args->{do_title} or $args->{do_pages} )
{
	# Parse sch files
	@files = @{Parse::GEDA::Gschem::readSchFiles( \@schFiles )};

	update_xref if $args->{do_xref};
	update_titleblock( $args ) if $args->{do_title} or $args->{do_pages};

	# Write changes to sch files
	Parse::GEDA::Gschem::writeSchFiles( \@files );
}

print "Done...\n";
