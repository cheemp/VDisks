#!/usr/bin/perl
#
# Script to add disks on a VIO Server
#
# Author: Jacob Yundt
#
# REV: 1.1.P (Valid are A, B, D, T and P)
#
# REV LIST:
# DATE: Jan 4, 2012
# BY: cheek
# MODIFICATION: Suppressed innocuous cfgdev errors
#               Accomodated profile names longer than 10 chars
#
# Usage: ./addVDisks.pl <hostname> <file containing serial #'s>
# More comments
#

$IOSPATH="/usr/ios/cli";
$ioscli="$IOSPATH/ioscli";
$VSCSI="/dsl/hmc-reports/P_VSCSI.csv";
$LPAR="/dsl/hmc-reports/P_LPAR.csv";
$ALLSYSTEMS="/system/params/all_systems";

use Data::Dumper;
use Getopt::Std;

getopts('hPfvaAEN');

if($opt_f){
	$force="true";
}

if($opt_P){
	$preview="true";
}

if($opt_v){
	$setvhost="true";
}

if ($opt_E){
	$setASM="true";
}
if ($opt_N){
	$newASM="true";
}

sub printHelp {
	print "Usage:\taddVDisks.pl [-h] [-P] [-a] [-E|-N] <hostname> <file>\n";
	print "\thostname=hostname of system\n";
	print "\tfile=file containing list of serial numbers\n";
	print "-a: alternate disks on the client LPAR (if LPAR is running)\n";
	print "-h: Print this help screen\n";
	print "-P: Preview only, display all commands before running\n\n";
	print "-E: do not add PVIDs to disks. {FOR EXISTING ASM DISKS / MIGRATIONS ONLY}\n";
	print "-N: clear PVIDs for NEW ASM disks. {FOR NEW ASM DISKS ONLY}\n";
	print "\t(NOTE: Do not use these options on NON-ASM disks.)\n";
	exit 0;
}

if ($opt_a){
	$alternate="true";
}

if($opt_h){
	printHelp();
}

if(@ARGV != 2){
	printHelp();
}

$host=$ARGV[0];
$serials_file=$ARGV[1];
chomp($SSHhost=`grep -w $host $ALLSYSTEMS`);
#open(FILE,$ARGV[1]) || die("Unable to open file \"@ARGV[1]\"\nExiting.\n");
open(FILE,$serials_file) || die("Unable to open file \"serials_file\"\nExiting.\n");
####updated so that you can directly copy/paste JB's e-mail into a txt file
## aka: awk for the 4th column!

#chomp(@input_serials=<FILE>);
chomp(@temp_input_serials=<FILE>);
close(FILE);

foreach(@temp_input_serials){
	if( $_ =~ m/[A-F0-9]{32}/){
		if ($& ne ""){
			push (@input_serials,$&);
		}
	}
}

####check to make sure this is a real node###

system("grep -qi $host $ALLSYSTEMS");

if ($? ne 0){
	print "Warning: $host not found in all_systems.\nIs this a real node?\n";
#	exit 1;
}

chomp(@profiles=`grep -wi $host $LPAR | cut -f 2,3 -d , | sort `);

if(@profiles <= 0){
	print "Error, no profiles were detected.\n";
	exit 1;
}

if (@profiles != 1){
	print "Warning: multiple profiles were detected for this node.\n";
	#print "(cleanup your old migrated profiles.)\n\n";
	$profile="";
	until ($profile ne ""){	
		$counter=0;
		foreach (@profiles){
			#print "$_\n";
			@temp_array=split(/,/,$_);
			chomp(@temp_array[0]=`echo $temp_array[0] | cut -c 23-25`);
			#print "$temp_array[1]: $temp_array[0]\n";
			print "$counter: $temp_array[0] ($temp_array[1])\n";
			$counter++;
		}
		$counter--;
		print "Please select a profile [0-$counter]: ";
		chomp($input=<STDIN>);
		if($input !~ m/^[0-9]+$/){
			print "Error!\nInvalid Input, hit enter to continue\n";
			$null=<STDIN>;
			redo;
		}else{
			if($input < 0 || $input > $counter){
				print "Error!\nInvalid Input, hit enter to continue\n";
				$null=<STDIN>;
				redo;
			}else{
				chomp($profile=`echo $profiles[$input] | cut -f 1 -d ,`);
			}
		}
	}
}else{
	chomp($profile=`echo $profiles[0] | cut -f 1 -d ,`);
}

chomp(@vios=`grep $host $VSCSI | grep $profile |cut -f 3 -d "," | grep -i vio|sort | uniq`);
if ( @vios == 0){
	print "Warning: VIO servers for $host not detected.\n";
	until($input =~ /^y$/i || $input =~ /^n$/i){
		print "Do you want to regenerate the HMC reports [y/n]: ";
		chomp($input=<STDIN>);
	}

	if ($input =~ /^n$/i){
		print "Exiting.\n";
		exit 1;
	}
	
	if ($input =~ /^y$/i){
		print "Regenerating HMC Reports...";
		system("/dsl/hmc-reports/LPARConfig.pl >/dev/null 2>&1");	
		if($? == 0){
			print "COMPLETED\n";
		}else{
			print "FAILED.\nExiting.\n";
			exit 1;
		}
	}
	chomp(@vios=`grep $host $VSCSI | cut -f 3 -d "," | grep -i vio|sort|uniq`);
	if (@vios == 0){
		print "Error, VIO Servers for $host STILL can't be found.\n";
		print "Did you create your vscsi device(s}?\n";
		exit 1;
	}
#} elsif (@vios != 2){
	#print "Warning: incorrect number of VIOS servers detected.\n";
	#print "VIO Servers for $host:\n";	
	#foreach (@vios){
		#print "$_\n";
	#}
	#exit 1;
}

####ok, starting the actual biznaz###

foreach $currentVIO (@vios){

	print "\n###### $currentVIO ######\n\n";
	#assign some additional variables

	print "Discovering new disks...";
	`ssh $currentVIO "$ioscli cfgdev" 2>/dev/null`;
	print "COMPLETE\n";
	print "Identifying vhost...";	

	chomp(@adapters=`grep $host $VSCSI | grep $currentVIO|grep server | cut -f 5 -d "," | sort `);
	foreach $tempAdapter (@adapters){
		chomp($vhost=`ssh $currentVIO "$ioscli lsmap -all -fmt \",\" -field svsa physloc | grep -w C$tempAdapter |cut -f 1 -d ","`);
		push(@vhosts,$vhost);
	}
	print "COMPLETE\n";
	$numvhosts=@vhosts;
	if ($numvhosts > 1){
		$vhost="";	
		until ($vhost ne ""){ 
			$counter=0;
			foreach (@vhosts){
				print "$counter: $_\n";
				$counter++;
			}
			$counter--;
			print "Please select a vhost [0-$counter]: ";
			chomp($input=<STDIN>);
			if($input !~ m/^[0-9]+$/){
				print "Error!\nInvalid input, hit enter to continue\n";
				$null=<STDIN>;
				redo;
			}else{
				if($input < 0 || $input > $counter){
					print "Error!\nInvalid input, hit enter to continue\n";
					$null=<STDIN>;
					redo;
				}else{
					$vhost=$vhosts[$input];
				}
			}
		}

	}else{
		$vhost=$vhosts[0];
	}
	print "Searching for free disks...";
	#chomp(@freeDisks=`ssh $currentVIO "$ioscli lspv -free" | grep -i hdisk | awk '{print \$1}'`);
	#IF YOU ARE HAVING ISSUES with dpm vio mappings, TRIPLE CHECK YOUR SERIAL FILE and comment about line with lspv -free and uncomment line below with just lspv command
	chomp(@freeDisks=`ssh $currentVIO "$ioscli lspv " | grep -i hdisk | awk '{print \$1}'`);
	print "COMPLETE\n";
	print "Building list of serial numbers...";
	for (@freeDisks){
		#Switching to odmget commands rather than lscfg
        	#this switch should make everything roughly 2x faster
        	#the next step will be to only have one ssh command pump it into a hash
		#chomp($serial=`ssh $currentVIO "lscfg -vpl $_ " | grep -i serial | cut -f 16 -d .`);
		chomp($serial=`ssh $currentVIO "odmget CuAt" | grep -wp $_ | grep -p unique_id | grep -i value | cut -f 2 -d \\"`);
        	$serial=substr($serial,5,32);
		
		$serials{$serial}=$_;
	}
	print "COMPLETE\n";

	print "Verifying disks are correctly presented to $currentVIO...";
	foreach (@input_serials){	
		if (!exists $serials{$_}){
			print"FAILED!\n";
			print "Error: Serial $_ not found on $currentVIO.\nExiting.\n";
			exit 1;
		}
	}
	print "COMPLETE\n";

	##I can do this better
	system("ssh $currentVIO \"$ioscli lsmap -vadapter $vhost\" | grep -q \"NO VIRTUAL TARGET DEVICE FOUND\"");
	#if ($? == 0  && !$setvhost){
	if ($? == 0  && $numvhosts==1){
		print "\nWarning: root disk NOT detected.\n";
		until (exists $serials{$root}){
			print "\nEnter the serial number for the root disk: ";
			chomp($root=<STDIN>);
		}

if (length $host > 10){
	$host=substr($host, 0, 10);
	print "\nWarning: Profile name longer than 10 chars\nTruncating to $host\n\n";
}
		###THIS IS WHERE THE SHIT GETS REAL, SON!###
		if ($preview ){
			#print "`ssh $currentVIO \"$ioscli chdev -dev $serials{$root} -attr pv=yes\"`\n";
                	#print "`ssh $currentVIO \"$ioscli chdev -dev $serials{$root} -attr reserve_policy=no_reserve\"`\n";
			print "PREVIEW: ssh $currentVIO \"$ioscli chdev -dev $serials{$root} -attr queue_depth=20\"\n";
                	print "PREVIEW: ssh $currentVIO \"$ioscli mkvdev -vdev $serials{$root} -vadapter $vhost -dev $host\_rt_1\"\n";
		}else{
			print "Creating root disk ($host\_rt_1)...";
			#Check to see if we have an ASM disk header
			#if we do, abort!
			system("ssh $currentVIO \"lquerypv -h /dev/$serials{$root}\" | grep -q ORCLDISK");
			if ($? == 0 && !$setASM){
				print "FAILED!\nASM disk headers were detected on $serials{$root}!\n";
				print "(exiting for safety.)\n\n";
				exit 1;
			}
			
			if ($newASM){
				`ssh $currentVIO "$ioscli chdev -dev $serials{$root} -attr pv=clear"`;
			}elsif ($setASM){
				`ssh $currentVIO "$ioscli chdev -dev $serials{$root} -attr pv=no"`;
			}else{
				`ssh $currentVIO "$ioscli chdev -dev $serials{$root} -attr pv=yes"`;
			}
			`ssh $currentVIO "$ioscli chdev -dev $serials{$root} -attr reserve_policy=no_reserve"`;
			`ssh $currentVIO "$ioscli mkvdev -vdev $serials{$root} -vadapter $vhost -dev $host\_rt_1" 2>/dev/null`;
			delete($serials{$root});
			print "COMPLETE\n";
		}	
		##start adding disks from _da_1 since this is new?
		## I think that makes sense
		$counter=0;
		foreach $serial (sort @input_serials){
			if ($serial eq $root){
				next;
			}
			$counter++;
			if ($preview){
				print "PREVIEW: ssh $currentVIO \"$ioscli mkvdev -vdev $serials{$serial} -vadapter $vhost -dev $host\_da_$counter\"\n";
			}else{
				print "Adding $serial $host\_da_$counter...";
				#Check to see if we have an ASM disk header
                        	#if we do, abort!
                        	system("ssh $currentVIO \"lquerypv -h /dev/$serials{$serial}\" | grep -q ORCLDISK");
                        	if ($? == 0 && !$setASM){
					print "FAILED!\nASM disk headers were detected on $serials{$serial}!\n";
					print "(exiting for safety.)\n\n";
                                	exit 1;
                        	}

				if ($newASM){
					`ssh $currentVIO "$ioscli chdev -dev $serials{$serial} -attr pv=clear"`;
				}elsif ($setASM){
					`ssh $currentVIO "$ioscli chdev -dev $serials{$serial} -attr pv=no"`;
				}else{
					`ssh $currentVIO "$ioscli chdev -dev $serials{$serial} -attr pv=yes"`;
				}
				`ssh $currentVIO "$ioscli chdev -dev $serials{$serial} -attr reserve_policy=no_reserve"`;
				`ssh $currentVIO "$ioscli mkvdev -vdev $serials{$serial} -vadapter $vhost -dev $host\_da_$counter" 2>/dev/null`;
				print "COMPLETE\n";
			}
			
		}
	}else{
	
		`ssh $currentVIO "$ioscli lsmap -vadapter $vhost -field vtd" | grep -i vtd | grep -qi vtscsi`;
		if($? == 0){
			#chomp($last=`ssh $currentVIO "$ioscli lsmap -vadapter $vhost -field vtd" | grep -i vtd | cut -d i -f 2 | sort | tail -n 1`);
			chomp($last=`ssh $currentVIO "$ioscli lsdev -virtual -state Available -field name "| grep -i vtscsi | cut -d i -f 2 | sort -n | tail -n 1`);
			$prefix="vtscsi";
		}else{
			chomp($last=`ssh $currentVIO "$ioscli lsmap -vadapter $vhost -field vtd" | grep -i vtd | grep -v _rt_ | awk '{print \$2}' | sort -n -t _ +2 | tail -n 1`);
			chomp($prefix=`echo $last | cut -f 1,2 -d _` );
		
		if ($prefix eq ""){
			#if($setvhost){
			if($numvhosts>1){
				#chomp($vhost2=`echo $vhost | cut -f 2 -d t1`);
				#$prefix="$host\_da$vhost2\_";
				$prefix="$host\_da$numvhosts\_";	
			}else{
				$prefix="$host\_da_";
			}
		}else{
			chomp($prefix=$prefix."_");
		}
		}
		if ($prefix eq "vtscsi"){
			$counter=$last;
		}else{
			chomp($counter=`echo $last | cut -f 3 -d _`);
		}

		foreach $serial (sort @input_serials){
			$counter++;
			if ($preview){
				print "PREVIEW: ssh $currentVIO \"$ioscli mkvdev -vdev $serials{$serial} -vadapter $vhost -dev $prefix$counter\"\n";
			}else{
				print "Adding $serial $prefix$counter...";
				#Check to see if we have an ASM disk header
				#if we do, abort!
				system("ssh $currentVIO \"lquerypv -h /dev/$serials{$serial}\" | grep -q ORCLDISK");
				if ($? == 0 && !$setASM){
					print "FAILED!\nASM disk headers were detected on $serials{$serial}!\n";
					print "(exiting for safety.)\n\n";
					exit 1;
				}
				if ($newASM){
					`ssh $currentVIO "$ioscli chdev -dev $serials{$serial} -attr pv=clear"`;
				}elsif ($setASM){
					`ssh $currentVIO "$ioscli chdev -dev $serials{$serial} -attr pv=no"`;
				}else{
					`ssh $currentVIO "$ioscli chdev -dev $serials{$serial} -attr pv=yes"`;
				}
                                `ssh $currentVIO "$ioscli chdev -dev $serials{$serial} -attr reserve_policy=no_reserve"`;
                                `ssh $currentVIO "$ioscli mkvdev  -vdev $serials{$serial} -vadapter $vhost -dev $prefix$counter" 2>/dev/null`;
				print "COMPLETE\n";
			}
		}
	
	}

	print "$currentVIO: FINISHED\n\n";
	###just added on 8/26 in case VIO #2 doesn't match VIO #1
	###clear the arrays just to be safe
	undef %serials;
	undef @freeDisks;
	undef @vhosts;
}

##
## Added on 12/15 
## run the alternate disk script on the LPAR
##
if ($alternate){
	print "Alternating paths on $host...";
	system("ssh $SSHhost \"cfgmgr ; /dsl/VIOS_Scripts/checkVIOPath.pl -f >/dev/null 2>&1\"");
	if ($? != 0){
		print "FAILED!\n";
	}else{
		print "COMPLETE\n";
	}
}
