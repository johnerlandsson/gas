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
#
# gas.pl 
# This script is a part of the gEDA Automation Schematic bundle.
# It handles updating the titleblock and crossreferences between components
# and pages.

use 5.18.4;

use Parse::GEDA::Gschem;
use Data::Dumper;
no warnings 'experimental::smartmatch';

$Parse::GEDA::Gschem::ERRORFILENAME = 'error.log';

# ========================================================================================================
# usage
# ========================================================================================================
# Print usage information
#
sub usage()
{
	say "Usage $0 [-htx]";
	say "";
	say "-b -bck\t\tCreate backup before performing actions.";
	say "-h -help\t\tDisplay this help.";
	say "-x -xref\t\tUpdate crossreferences on all schematics in folder.";
	say "-t -title [TITLE]\tSets the title attribute on titleblocks.";
	say "-p -pages\t\tUpdates the page number part of titleblocks.";
	say "-a -author [AUTHOR]\tSets the drawn_by attribute on titleblocks";
	say "";
}

# ========================================================================================================
# chk_args
# ========================================================================================================
# Handle command line arguments
#
sub chk_args()
{
	our @ARGV;
	
	my $args = { 
			do_backup => 0, 
			do_xref => 0, 
			do_title => 0, 
			titleblock_title => "", 
			do_pages => 0, 
			do_drawn_by => 0, 
			titleblock_drawn_by => "" 
		   };

	# iterate arguments
	for( my $arg_idx = 0; $arg_idx < @ARGV; $arg_idx++ )
	{
		if( $ARGV[$arg_idx] =~ /^-x(ref)?$/ )
		{
			$args->{do_xref} = 1;
		}
		elsif( $ARGV[$arg_idx] =~ /^-t(itle)?$/ )
		{
			if( $arg_idx ge (@ARGV - 1) )
			{
				say STDERR "No title given...";
				next;
			}

			$args->{do_title} = 1;
			$arg_idx++;
			$args->{titleblock_title} = $ARGV[$arg_idx];
		}
		elsif( $ARGV[$arg_idx] =~ /^-b(ck)?$/ )
		{
			$args->{do_backup} = 1;
		}
		elsif( $ARGV[$arg_idx] =~ /^-p(ages)?$/ )
		{
			$args->{do_pages} = 1;
		}
		elsif( $ARGV[$arg_idx] =~ /^-a(uthor)?$/ )
		{
			if( $arg_idx ge (@ARGV - 1) )
			{
				say STDERR "No author given...";
				next;
			}

			$args->{do_drawn_by} = 1;
			$arg_idx++;
			$args->{titleblock_drawn_by} = $ARGV[$arg_idx];
		}
		elsif( $ARGV[$arg_idx] =~ /^-h(elp)?$/ )
		{
			usage();
		}
		else
		{
			usage();
			say STDERR "\nUnknown argument: " . $ARGV[$arg_idx];
			exit 1;
		}
	}

	return $args;
}

# ========================================================================================================
# titleblock_origin
# ========================================================================================================
# Returns the xy coordinates of titleblock origin if any.
#
sub titleblock_origin()
{
	our @files;
	my $ret = { x => -1, y => -1 };

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

			$ret->{x} = $files[$file_idx]->{objects}->[$object_idx]->{x};
			$ret->{y} = $files[$file_idx]->{objects}->[$object_idx]->{y};
		}
	}

	if( $ret->{x} lt 0 or $ret->{y} lt 0  )
	{
		say STDERR "titleblock_origin: No valid titleblock found";
		exit 1;
	}
			
	return $ret;
}

# ========================================================================================================
# map_titleblock
# ========================================================================================================
# map XY cordinates to titleblock
# used by update_xref
#
#
sub map_titleblock( $$ )
{
	my $x = $_[0]->{x};
	my $y = $_[0]->{y};
	my $tb_origin = $_[1];
	my $border_step = 1968;

	use POSIX;
	my $x_diff = $x - $tb_origin->{x};
	my $ret_x = ceil( $x_diff / $border_step );
	if( $ret_x gt 9 or $ret_x lt 1 )
	{
		say STDERR "map_titleblock: Invalid X-position $ret_x, $x";
		exit 1;
	}
	
	my $y_diff = $y - $tb_origin->{y};
	my $ret_y = chr( ($y_diff / $border_step) + 65 );
	if( $ret_y gt 'F' or $ret_y lt 'A' )
	{
		say STDERR "map_titleblock: Invalid Y-position $ret_y, $y";
		exit 1;
	}

	return $ret_y . $ret_x;
}

# ========================================================================================================
# object_refdes_cords
# ========================================================================================================
# Returns origin of object's refdes label
#
sub object_refdes_cords( $ )
{
	my $object = shift;
	my $ret = { x => -1, y => -1 };

	foreach my $catt ( @{$object->{Attributes}} )
	{
		if( $catt->{name} eq "refdes" )
		{
			$ret->{x} = $catt->{x};
			$ret->{y} = $catt->{y};
			return $ret;
		}
	}



	return $ret;
}

# ========================================================================================================
# hlp_update_xref
# ========================================================================================================
# Helper function for update_xref
# Reiterates all files and components looking for the refdes that was found by update_xref
# then updates or adds the xref attribute with coordinates mapped to the titleblock
#
sub hlp_update_xref( $$$$ )
{
	my $b_file_idx = $_[0];
	my $b_object_idx = $_[1];
	my $b_refdes = $_[2];
	my $xref_str = $_[3];

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
						$files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$xref_idx]->{value} = $xref_str;
					}
					#Otherwise create new xref attribute
					else
					{
						# place the xref attribute on components origin
						my %new_attr = (
								alignment => '0',
								show_name_value => '1',
								value => $xref_str,
								angle => '0',
								x => $files[$file_idx]->{objects}->[$object_idx]->{x},
								size => '6',
								y => $files[$file_idx]->{objects}->[$object_idx]->{y} - 10,
								color => '5',
								name => 'xref',
								type => 'T',
								num_lines => '1',
								visibility => '1'
							       );

						say "Adding new xref attribute to " . $refdes_value . " on page " . ($file_idx + 1);
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
sub update_xref()
{
	our @files;

	# iterate files
	for( my $file_idx = 0; $file_idx < @files; $file_idx++ )
	{
		# next if file has objects in it
		next if( !($files[$file_idx]->{objects}) );

		# fetch titleblock origin once every sheet
		my $tb_origin = titleblock_origin();

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
				
				my $cords = object_refdes_cords( $files[$file_idx]->{objects}->[$object_idx] );
				
				say "Found valid component " . $refdes . " with attribute xref_master=1 in " . $files[$file_idx]->{fileName} . " at X" . $cords->{x} . "Y" . $cords->{y};
				
				my $xref_str = ($file_idx + 1) . '-' . map_titleblock( $cords, $tb_origin );
				hlp_update_xref( $file_idx, $object_idx, $refdes, $xref_str );
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
sub update_titleblock( $ )
{
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
			
			say "Found titleblock in: " . $files[$file_idx]->{fileName};
			
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
					if( $args->{do_drawn_by} )
					{
						$files[$file_idx]->{objects}->[$object_idx]->{Attributes}->[$attr_idx]->{value} = $args->{titleblock_drawn_by} when 'drawn_by';
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
if( @schFiles le 0 )
{
	say STDERR "No *.sch files in current folder...";
	exit 1;
}

# back up schematic files
if( $args->{do_backup} )
{
	say "Creating backup...";
	Parse::GEDA::Gschem::bakSchFiles( \@schFiles ); 
}

if( $args->{do_xref} or 
    $args->{do_title} or 
    $args->{do_pages} or
    $args->{do_drawn_by} )
{
	# Parse sch files
	@files = @{Parse::GEDA::Gschem::readSchFiles( \@schFiles )};

	update_xref() if $args->{do_xref};
	update_titleblock( $args ) if $args->{do_title} or $args->{do_pages} or $args->{do_drawn_by};

	# Write changes to sch files
	Parse::GEDA::Gschem::writeSchFiles( \@files );
}

exit 0;
