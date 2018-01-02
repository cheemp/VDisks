#!/usr/bin/perl
#
# Script to delete disks on a VIO Server
#
# Author: Jacob Yundt
#
# REV: 1.1.P (Valid are A, B, D, T and P)
#
# REV LIST:
# DATE: Jan 4, 2012
# BY: cheek
# MODIFICATION: Suppressed innocuous cfgdev errors
# Date: Aug 20, 2013
# BY: Wiebalk
# MODIFICATION: Add explicit grep now returns only correct vhost
#
# Usage: ./delVDisks.pl <hostname> <file containing serial #'s>

$IOSPATH="/usr/ios/cli";
$ioscli="$IOSPATH/ioscli";
$VSCSI="/dsl/hmc-reports/P_VSCSI.csv";
$LPAR="/dsl/hmc-reports/P_LPAR.csv";
$ALLSYSTEMS="/system/params/all_systems";

use Data::Dumper;
use Getopt::Std;

getopts('hPfvra');

if($opt_f){
	$force="true";
}

if($opt_P){
	$preview="true";
}

if($opt_v){
	$setvhost="true";
}

sub printHelp {
	print "Usage:\tdelVDisks.pl [-h|-P]  <hostname> <file>\n";
	print "\thostname=hostname of system\n";
	print "\tfile=file containing list of serial numbers\n";
	print "-h: Print this help screen\n";
	print "-P: Preview only, display all commands before running\n";
	exit 0;
}

if($opt_h){
	printHelp();
}

if(@ARGV != 2){
	printHelp();
}

$host=$ARGV[0];
$serials_file=$ARGV[1];
#open(FILE,$ARGV[1]) || die("Unable to open file \"@ARGV[1]\"\nExiting...\n");
open(FILE,$serials_file) || die("Unable to open file \"serials_file\"\nExiting...\n");
####updated so that you can directly copy/paste JB's e-mail into a txt file
## aka:	 awk for the 4th column!
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
		print "Exiting...\n";
		exit 1;
	}
	
	if ($input =~ /^y$/i){
		print "Regenerating HMC Reports...";
		system("/dsl/hmc-reports/LPARConfig.pl >/dev/null 2>&1");	
		if($? == 0){
			print "COMPLETED\n";
		}else{
			print "FAILED!\nExiting...\n";
			exit 1;
		}
	}
	chomp(@vios=`grep $host $VSCSI | cut -f 3 -d "," | grep -i vio|sort|uniq`);
	if (@vios == 0){
		print "Error, VIO Servers for $host STILL can't be found.\n";
		print "Did you create you vscsi devices?\n";
		exit 1;
	}
#} elsif (@vios != 2){
	#print "Warning: incorrect number of VIOS servers detected.\n";
	#print "VIO Servers for $host:\n";	
	#foreach (@vios){
	#	print "$_\n";
	#}
	#exit 1;
}

####ok, starting the actual biznaz###

#print "@vios\n";

foreach $currentVIO (@vios){
	print "\n###### $currentVIO ######\n\n";

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

	print "Searching for disks used by $host...";
	chomp(@usedDisks=`ssh $currentVIO "$ioscli lsmap -vadapter $vhost -field backing" | grep -i hdisk | awk '{print \$3}'`);
	print "COMPLETE\n";

	print "Building list of serial numbers...";
	for (@usedDisks){
		#Switching to odmget commands rather than lscfg
        	#this switch should make everything roughly 2x faster
        	#the next step will be to only have one ssh command pump it into a hash
		#chomp($serial=`ssh $currentVIO "lscfg -vpl $_ " | grep -i serial | cut -f 16 -d .`);
        	chomp($serial=`ssh $currentVIO "odmget CuAt" | grep -wp $_ | grep -p unique_id | grep -i value | cut -f 2 -d \\"`);
        	$serial=substr($serial,5,32);
		#print "$_: $serial\n";
		$serials{$serial}=$_;
	}
	print "COMPLETE\n";
	print "Verifying disks are correctly mapped to $host...";
	foreach (@input_serials){	
		if (!exists $serials{$_}){
			print"FAILED!\n";
			print "Error: Serial $_ not mapped to $host.\nExiting...\n";
			exit 1;
		}
	}
	print "COMPLETE\n";

	##I can do this better

	foreach (@input_serials){

		if($preview){
			print "PREVIEW: `ssh $currentVIO \"$ioscli rmvdev -vdev $serials{$_}\"`\n";
		}else{
			print "Removing $_ from $host...";
			`ssh $currentVIO "$ioscli rmvdev -vdev $serials{$_}" 2>/dev/null`;
			print "COMPLETE\n";
			print "Deleting $serials{$_} from $currentVIO...";
			`ssh $currentVIO "rmdev -dl $serials{$_}" 2>/dev/null`;
			print "COMPLETE\n";
		}
	}
	undef %serials;
	undef @usedDisks;
	undef @vhosts;
}
